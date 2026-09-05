defmodule TeslaMateWeb.MobileApiController do
  use TeslaMateWeb, :controller

  import Ecto.Query

  alias TeslaMate.{Log, Repo, Vehicles}
  alias TeslaMateWeb.MobileHistory
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.{Charge, ChargingProcess, Drive, Position, Update}

  plug :validate_vehicle
       when action in [:drives, :charging, :statistics, :updates, :battery_health]

  plug :load_record when action in [:drive, :charge]
  plug :validate_history when action in [:drives, :charging]

  @fields ~w(
    state since healthy latitude longitude heading battery_level usable_battery_level
    ideal_battery_range_km est_battery_range_km rated_battery_range_km charging_state
    charge_limit_soc charger_power plugged_in speed outside_temp inside_temp is_climate_on
    locked sentry_mode odometer version geofence model trim_badging exterior_color
    windows_open doors_open trunk_open frunk_open charge_port_door_open shift_state
    time_to_full_charge charger_actual_current charger_voltage charger_phases charge_energy_added
    update_available update_version update_status is_preconditioning is_user_present
    tpms_pressure_fl tpms_pressure_fr tpms_pressure_rl tpms_pressure_rr
    tpms_soft_warning_fl tpms_soft_warning_fr tpms_soft_warning_rl tpms_soft_warning_rr
  )a

  def vehicles(conn, _params) do
    data =
      Log.list_cars()
      |> Enum.map(fn car ->
        summary = Vehicles.summary(car.id)

        summary
        |> Map.take(@fields)
        |> Map.new(fn {key, value} -> {key, json_value(value)} end)
        |> Map.merge(%{
          id: car.id,
          name: summary.display_name || car.name || "Tesla",
          vin_suffix: String.slice(car.vin || "", -6, 6)
        })
      end)

    json(conn, %{data: data, generated_at: DateTime.utc_now()})
  end

  def drives(conn, _params) do
    query =
      Drive
      |> where([d], d.car_id == ^conn.assigns.mobile_car_id)
      |> preload([
        :start_address,
        :end_address,
        :start_geofence,
        :end_geofence,
        :start_position,
        :end_position
      ])

    json(conn, MobileHistory.page(query, conn.assigns.history_options, &drive_json/1))
  end

  def drive(conn, _params) do
    drive =
      Repo.preload(conn.assigns.mobile_record, [
        :start_address,
        :end_address,
        :start_geofence,
        :end_geofence,
        :start_position,
        :end_position
      ])

    {positions, sampling} =
      Position
      |> where([p], p.drive_id == ^drive.id)
      |> MobileHistory.samples(Position, [:latitude, :longitude, :speed, :date])

    data =
      drive_json(drive)
      |> Map.put(:positions, Enum.map(positions, &json_map/1))
      |> Map.put(:sampling, sampling)

    json(conn, %{data: data})
  end

  def charging(conn, _params) do
    query =
      ChargingProcess
      |> where([c], c.car_id == ^conn.assigns.mobile_car_id)
      |> preload([:address, :geofence, :position])

    json(conn, MobileHistory.page(query, conn.assigns.history_options, &charge_json/1))
  end

  def charge(conn, _params) do
    process = Repo.preload(conn.assigns.mobile_record, [:address, :geofence, :position])

    {samples, sampling} =
      Charge
      |> where([c], c.charging_process_id == ^process.id)
      |> MobileHistory.samples(Charge, [
        :date,
        :battery_level,
        :charger_power,
        :charge_energy_added,
        :outside_temp
      ])

    samples =
      Enum.map(samples, fn sample ->
        {energy, sample} = Map.pop(sample, :charge_energy_added)
        sample |> Map.put(:energy_added_kwh, energy) |> json_map()
      end)

    data = charge_json(process) |> Map.put(:samples, samples) |> Map.put(:sampling, sampling)
    json(conn, %{data: data})
  end

  def statistics(conn, _params) do
    car_id = conn.assigns.mobile_car_id
    cutoff = DateTime.add(DateTime.utc_now(), -370, :day)

    drive_stats =
      Repo.one(
        from d in Drive,
          where: d.car_id == ^car_id and not is_nil(d.end_date),
          select: %{
            count: count(d.id),
            distance_km: coalesce(sum(d.distance), 0.0),
            duration_min: coalesce(sum(d.duration_min), 0)
          }
      )

    charge_stats =
      Repo.one(
        from c in ChargingProcess,
          where: c.car_id == ^car_id and not is_nil(c.end_date),
          select: %{
            count: count(c.id),
            energy_kwh: coalesce(sum(c.charge_energy_added), 0),
            cost: coalesce(sum(c.cost), 0)
          }
      )

    monthly_driving =
      Repo.all(
        from d in Drive,
          where: d.car_id == ^car_id and d.start_date >= ^cutoff and not is_nil(d.end_date),
          group_by: fragment("date_trunc('month', ?)", d.start_date),
          order_by: fragment("date_trunc('month', ?)", d.start_date),
          select: %{
            month: fragment("to_char(date_trunc('month', ?), 'YYYY-MM')", d.start_date),
            count: count(d.id),
            distance_km: coalesce(sum(d.distance), 0.0),
            duration_min: coalesce(sum(d.duration_min), 0)
          }
      )
      |> Enum.map(&json_map/1)

    monthly_charging =
      Repo.all(
        from c in ChargingProcess,
          where: c.car_id == ^car_id and c.start_date >= ^cutoff and not is_nil(c.end_date),
          group_by: fragment("date_trunc('month', ?)", c.start_date),
          order_by: fragment("date_trunc('month', ?)", c.start_date),
          select: %{
            month: fragment("to_char(date_trunc('month', ?), 'YYYY-MM')", c.start_date),
            count: count(c.id),
            energy_kwh: coalesce(sum(c.charge_energy_added), 0),
            cost: coalesce(sum(c.cost), 0)
          }
      )
      |> Enum.map(&json_map/1)

    json(conn, %{
      data: %{
        driving: json_map(drive_stats),
        charging: json_map(charge_stats),
        monthly_driving: monthly_driving,
        monthly_charging: monthly_charging
      }
    })
  end

  def geofences(conn, _params) do
    data =
      GeoFence
      |> order_by([g], asc: g.name)
      |> Repo.all()
      |> Enum.map(fn g ->
        json_map(%{
          id: g.id,
          name: g.name,
          latitude: g.latitude,
          longitude: g.longitude,
          radius: g.radius,
          billing_type: g.billing_type,
          cost_per_unit: g.cost_per_unit,
          session_fee: g.session_fee
        })
      end)

    json(conn, %{data: data})
  end

  def updates(conn, _params) do
    data =
      Update
      |> where([u], u.car_id == ^conn.assigns.mobile_car_id)
      |> order_by([u], desc: u.start_date)
      |> limit(100)
      |> select([u], %{
        id: u.id,
        start_date: u.start_date,
        end_date: u.end_date,
        version: u.version
      })
      |> Repo.all()
      |> Enum.map(&json_map/1)

    json(conn, %{data: data})
  end

  def battery_health(conn, _params) do
    car_id = conn.assigns.mobile_car_id

    data =
      Position
      |> where(
        [p],
        p.car_id == ^car_id and p.battery_level >= 80 and
          not is_nil(p.rated_battery_range_km) and p.rated_battery_range_km > 0
      )
      |> group_by([p], fragment("date_trunc('day', ?)", p.date))
      |> order_by([p], desc: fragment("date_trunc('day', ?)", p.date))
      |> limit(365)
      |> select([p], %{
        date: fragment("to_char(date_trunc('day', ?), 'YYYY-MM-DD')", p.date),
        full_range_km:
          fragment(
            "AVG((?::float / NULLIF(?, 0)) * 100)",
            p.rated_battery_range_km,
            p.battery_level
          ),
        odometer: avg(p.odometer),
        samples: count(p.id)
      })
      |> Repo.all()
      |> Enum.map(&json_map/1)

    json(conn, %{data: data})
  end

  defp drive_json(drive) do
    json_map(%{
      id: drive.id,
      car_id: drive.car_id,
      start_date: drive.start_date,
      end_date: drive.end_date,
      duration_min: drive.duration_min,
      distance_km: drive.distance,
      speed_max: drive.speed_max,
      power_max: drive.power_max,
      power_min: drive.power_min,
      outside_temp_avg: drive.outside_temp_avg,
      start_range_km: drive.start_ideal_range_km,
      end_range_km: drive.end_ideal_range_km,
      start_name: place_name(drive.start_geofence, drive.start_address),
      end_name: place_name(drive.end_geofence, drive.end_address),
      start_latitude: coordinate(drive.start_position, :latitude),
      start_longitude: coordinate(drive.start_position, :longitude),
      end_latitude: coordinate(drive.end_position, :latitude),
      end_longitude: coordinate(drive.end_position, :longitude)
    })
  end

  defp charge_json(charge) do
    json_map(%{
      id: charge.id,
      car_id: charge.car_id,
      start_date: charge.start_date,
      end_date: charge.end_date,
      duration_min: charge.duration_min,
      energy_added_kwh: charge.charge_energy_added,
      energy_used_kwh: charge.charge_energy_used,
      start_battery_level: charge.start_battery_level,
      end_battery_level: charge.end_battery_level,
      cost: charge.cost,
      outside_temp_avg: charge.outside_temp_avg,
      name: place_name(charge.geofence, charge.address),
      latitude: coordinate(charge.position, :latitude),
      longitude: coordinate(charge.position, :longitude)
    })
  end

  defp place_name(%{name: name}, _address) when is_binary(name), do: name
  defp place_name(_, %{display_name: name}) when is_binary(name), do: name
  defp place_name(_, _), do: "未知地点"

  defp coordinate(nil, _field), do: nil
  defp coordinate(struct, field), do: Map.get(struct, field)

  defp validate_vehicle(conn, _opts) do
    result =
      case conn.params do
        %{"car_id" => value} ->
          case positive_id(value, 32_767) do
            {:ok, id} -> {:ok, Repo.get(Log.Car, id)}
            :error -> :error
          end

        _ ->
          {:ok, Log.list_cars() |> List.first()}
      end

    case result do
      {:ok, %Log.Car{id: id}} -> assign(conn, :mobile_car_id, id)
      {:ok, nil} -> api_error(conn, :not_found, "vehicle_not_found")
      :error -> api_error(conn, :bad_request, "invalid_car_id")
    end
  end

  defp validate_history(conn, _opts) do
    case MobileHistory.options(conn.params) do
      {:ok, options} -> assign(conn, :history_options, options)
      {:error, error} -> api_error(conn, :bad_request, error)
    end
  end

  defp load_record(conn, _opts) do
    with {:ok, id} <- positive_id(conn.params["id"], 2_147_483_647) do
      schema = if action_name(conn) == :drive, do: Drive, else: ChargingProcess
      query = where(schema, [r], r.id == ^id)

      case conn.params do
        %{"car_id" => value} ->
          case positive_id(value, 32_767) do
            {:ok, car_id} -> assign_record(conn, where(query, [r], r.car_id == ^car_id))
            :error -> api_error(conn, :bad_request, "invalid_car_id")
          end

        _ ->
          assign_record(conn, query)
      end
    else
      _ -> api_error(conn, :bad_request, "invalid_id")
    end
  end

  defp assign_record(conn, query) do
    case Repo.one(query) do
      nil -> api_error(conn, :not_found, "record_not_found")
      record -> assign(conn, :mobile_record, record)
    end
  end

  defp positive_id(value, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= maximum -> {:ok, id}
      _ -> :error
    end
  end

  defp positive_id(_, _maximum), do: :error

  defp api_error(conn, status, error) do
    conn |> put_status(status) |> json(%{error: error}) |> halt()
  end

  defp json_map(map), do: Map.new(map, fn {key, value} -> {key, json_value(value)} end)

  defp json_value(%Decimal{} = value), do: Decimal.to_float(value)
  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(value) when is_boolean(value) or is_nil(value), do: value
  defp json_value(:unknown), do: nil
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value), do: value
end
