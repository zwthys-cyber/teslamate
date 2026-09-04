defmodule TeslaMateWeb.MobileApiController do
  use TeslaMateWeb, :controller

  import Ecto.Query

  alias TeslaMate.{Log, Repo, Vehicles}
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.{ChargingProcess, Drive, Position}

  @fields ~w(
    state since healthy latitude longitude heading battery_level usable_battery_level
    ideal_battery_range_km est_battery_range_km rated_battery_range_km charging_state
    charge_limit_soc charger_power plugged_in speed outside_temp inside_temp is_climate_on
    locked sentry_mode odometer version geofence model trim_badging exterior_color
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

  def drives(conn, params) do
    car_id = car_id(params)
    limit = page_limit(params)

    data =
      Drive
      |> where([d], d.car_id == ^car_id)
      |> order_by([d], desc: d.start_date)
      |> limit(^limit)
      |> preload([:start_address, :end_address, :start_geofence, :end_geofence, :start_position, :end_position])
      |> Repo.all()
      |> Enum.map(&drive_json/1)

    json(conn, %{data: data})
  end

  def drive(conn, %{"id" => id}) do
    drive =
      Drive
      |> Repo.get!(id)
      |> Repo.preload([:start_address, :end_address, :start_geofence, :end_geofence, :start_position, :end_position])

    positions =
      Position
      |> where([p], p.drive_id == ^drive.id)
      |> order_by([p], asc: p.date)
      |> select([p], %{latitude: p.latitude, longitude: p.longitude, speed: p.speed, date: p.date})
      |> Repo.all()
      |> Enum.map(&json_map/1)

    json(conn, %{data: Map.put(drive_json(drive), :positions, positions)})
  end

  def charging(conn, params) do
    car_id = car_id(params)

    data =
      ChargingProcess
      |> where([c], c.car_id == ^car_id)
      |> order_by([c], desc: c.start_date)
      |> limit(^page_limit(params))
      |> preload([:address, :geofence, :position])
      |> Repo.all()
      |> Enum.map(&charge_json/1)

    json(conn, %{data: data})
  end

  def statistics(conn, params) do
    car_id = car_id(params)

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

    json(conn, %{data: %{driving: json_map(drive_stats), charging: json_map(charge_stats)}})
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

  defp drive_json(drive) do
    json_map(%{
      id: drive.id,
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

  defp car_id(%{"car_id" => id}), do: String.to_integer(id)
  defp car_id(_), do: Log.list_cars() |> List.first() |> Map.fetch!(:id)

  defp page_limit(%{"limit" => value}) do
    value |> String.to_integer() |> min(500) |> max(1)
  rescue
    _ -> 100
  end

  defp page_limit(_), do: 100

  defp json_map(map), do: Map.new(map, fn {key, value} -> {key, json_value(value)} end)

  defp json_value(%Decimal{} = value), do: Decimal.to_float(value)
  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(value) when is_boolean(value) or is_nil(value), do: value
  defp json_value(:unknown), do: nil
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value), do: value
end
