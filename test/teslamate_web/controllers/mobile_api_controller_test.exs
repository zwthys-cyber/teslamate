defmodule TeslaMateWeb.MobileApiControllerTest do
  use TeslaMateWeb.ConnCase
  import Mock

  @token String.duplicate("a", 32)
  @vehicle_actions ~w(drives charging statistics updates battery_health)

  setup %{conn: conn} do
    previous = Application.fetch_env(:teslamate, :mobile_api_token)
    Application.put_env(:teslamate, :mobile_api_token, @token)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:teslamate, :mobile_api_token, value)
        :error -> Application.delete_env(:teslamate, :mobile_api_token)
      end
    end)

    {:ok, conn: put_req_header(conn, "authorization", "Bearer " <> @token)}
  end

  test "all mobile endpoints require authorization", %{conn: conn} do
    for path <-
          ~w(vehicles drives drives/1 charging charging/1 statistics geofences updates battery_health) do
      response = conn |> delete_req_header("authorization") |> get("/api/mobile/v1/" <> path)
      assert json_response(response, 401) == %{"error" => "unauthorized"}
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "invalid or unconfigured tokens fail closed", %{conn: conn} do
    for configured <- [nil, "", "short", String.duplicate("b", 32)] do
      Application.put_env(:teslamate, :mobile_api_token, configured)

      assert conn |> get("/api/mobile/v1/vehicles") |> json_response(401) ==
               %{"error" => "unauthorized"}
    end
  end

  test "empty database returns an empty vehicle list", %{conn: conn} do
    response = get(conn, "/api/mobile/v1/vehicles")
    assert %{"data" => [], "generated_at" => timestamp} = json_response(response, 200)
    assert {:ok, _, _} = DateTime.from_iso8601(timestamp)
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end

  test "missing vehicles return a structured 404", %{conn: conn} do
    for action <- @vehicle_actions, query <- ["", "?car_id=32767"] do
      assert conn |> get("/api/mobile/v1/" <> action <> query) |> json_response(404) ==
               %{"error" => "vehicle_not_found"}
    end
  end

  test "invalid vehicle IDs return 400 instead of raising", %{conn: conn} do
    for action <- @vehicle_actions,
        value <- ["abc", "0", "-1", "1x", "32768", "2147483648", ""] do
      assert conn
             |> get("/api/mobile/v1/" <> action, %{"car_id" => value})
             |> json_response(400) == %{"error" => "invalid_car_id"}
    end
  end

  test "malformed record IDs return 400", %{conn: conn} do
    for action <- ~w(drives charging), id <- ~w(abc -1 0 2147483648) do
      assert conn |> get("/api/mobile/v1/" <> action <> "/" <> id) |> json_response(400) ==
               %{"error" => "invalid_id"}
    end
  end

  test "a valid vehicle with no history returns empty collections and zero totals", %{conn: conn} do
    {:ok, car} = TeslaMate.Log.create_car(%{eid: 4242, vid: 404, vin: "test-vin"})

    for action <- ~w(drives charging updates battery_health) do
      assert %{"data" => []} =
               conn
               |> get("/api/mobile/v1/" <> action, %{"car_id" => to_string(car.id)})
               |> json_response(200)
    end

    data =
      conn
      |> get("/api/mobile/v1/statistics", %{"car_id" => to_string(car.id)})
      |> json_response(200)

    assert data["data"]["driving"]["count"] == 0
    assert data["data"]["monthly_driving"] == []
    assert data["data"]["monthly_charging"] == []
  end

  test "vehicle JSON preserves booleans and unknown values", %{conn: conn} do
    {:ok, car} = TeslaMate.Log.create_car(%{eid: 4242, vid: 404, vin: "123456789"})

    with_mock TeslaMate.Vehicles,
      summary: fn id ->
        assert id == car.id

        %TeslaMate.Vehicles.Vehicle.Summary{
          display_name: "Test car",
          state: :asleep,
          healthy: true,
          locked: false,
          battery_level: :unknown,
          latitude: nil
        }
      end do
      assert %{"data" => [vehicle]} = conn |> get("/api/mobile/v1/vehicles") |> json_response(200)
      assert vehicle["healthy"] == true
      assert vehicle["locked"] == false
      assert vehicle["battery_level"] == nil
      assert vehicle["latitude"] == nil
      assert vehicle["state"] == "asleep"
      assert vehicle["vin_suffix"] == "456789"
    end
  end

  test "history pagination is stable across equal timestamps and new inserts", %{conn: conn} do
    car = history_car()
    other = history_car()
    date = ~U[2026-09-01 08:00:00.123456Z]

    for {path, schema} <- history_types() do
      records = for _ <- 1..4, do: history_record(schema, car, date)
      history_record(schema, other, date)

      first =
        conn
        |> get("/api/mobile/v1/" <> path, %{"car_id" => to_string(car.id), "limit" => "2"})
        |> json_response(200)

      assert Enum.map(first["data"], & &1["id"]) ==
               records |> Enum.reverse() |> Enum.take(2) |> Enum.map(& &1.id)

      assert is_binary(first["pagination"]["next_cursor"])
      history_record(schema, car, DateTime.add(date, 60, :second))

      second =
        conn
        |> get("/api/mobile/v1/" <> path, %{
          "car_id" => to_string(car.id),
          "limit" => "2",
          "cursor" => first["pagination"]["next_cursor"]
        })
        |> json_response(200)

      assert Enum.map(second["data"], & &1["id"]) ==
               records |> Enum.take(2) |> Enum.reverse() |> Enum.map(& &1.id)

      assert second["pagination"]["next_cursor"] == nil
      assert Enum.all?(first["data"] ++ second["data"], &(&1["car_id"] == car.id))
    end
  end

  test "date filters include from, exclude to, and accept timezone offsets", %{conn: conn} do
    car = history_car()
    from = ~U[2026-08-31 16:00:00.000000Z]
    to = DateTime.add(from, 1, :day)

    for {path, schema} <- history_types() do
      history_record(schema, car, DateTime.add(from, -1, :second))
      included = history_record(schema, car, from)
      history_record(schema, car, to)

      body =
        conn
        |> get("/api/mobile/v1/" <> path, %{
          "car_id" => to_string(car.id),
          "from" => "2026-09-01T00:00:00+08:00",
          "to" => "2026-09-02T00:00:00+08:00"
        })
        |> json_response(200)

      assert Enum.map(body["data"], & &1["id"]) == [included.id]
      assert body["pagination"]["next_cursor"] == nil
    end
  end

  test "invalid history filters return a structured 400", %{conn: conn} do
    car = history_car()

    for {path, _} <- history_types(),
        invalid <- [
          %{"limit" => "0"},
          %{"limit" => "501"},
          %{"limit" => "2x"},
          %{"from" => "2026-09-01"},
          %{"to" => "invalid"},
          %{"from" => "2026-09-02T00:00:00Z", "to" => "2026-09-01T00:00:00Z"},
          %{"cursor" => "bad"},
          %{"cursor" => Base.url_encode64("[null,1]", padding: false)},
          %{"cursor" => String.duplicate("x", 513)}
        ] do
      assert conn
             |> get("/api/mobile/v1/" <> path, Map.put(invalid, "car_id", to_string(car.id)))
             |> json_response(400) ==
               %{"error" => "invalid_history_parameters"}
    end
  end

  test "details are scoped to the selected car and missing records return JSON", %{conn: conn} do
    car = history_car()
    other = history_car()

    for {path, schema} <- history_types() do
      record = history_record(schema, car, ~U[2026-09-01 08:00:00.000000Z])
      url = "/api/mobile/v1/" <> path <> "/" <> to_string(record.id)

      assert conn |> get(url, %{"car_id" => to_string(other.id)}) |> json_response(404) == %{
               "error" => "record_not_found"
             }

      assert conn |> get(url, %{"car_id" => "32768"}) |> json_response(400) == %{
               "error" => "invalid_car_id"
             }

      body = conn |> get(url, %{"car_id" => to_string(car.id)}) |> json_response(200)
      assert body["data"]["car_id"] == car.id
      assert body["data"]["sampling"] == %{"total" => 0, "returned" => 0, "downsampled" => false}

      assert conn |> get("/api/mobile/v1/" <> path <> "/2147483647") |> json_response(404) == %{
               "error" => "record_not_found"
             }
    end
  end

  test "drive routes are bounded and preserve endpoints", %{conn: conn} do
    car = history_car()
    date = ~U[2026-09-01 08:00:00.000000Z]
    drive = history_record(TeslaMate.Log.Drive, car, date)

    rows =
      for index <- 0..2000,
          do: %{
            car_id: car.id,
            drive_id: drive.id,
            date: DateTime.add(date, index, :second),
            latitude: Decimal.new("31.2"),
            longitude: Decimal.new("121.5"),
            speed: index |> rem(100)
          }

    TeslaMate.Repo.insert_all(TeslaMate.Log.Position, rows)

    body =
      conn
      |> get("/api/mobile/v1/drives/#{drive.id}", %{"car_id" => to_string(car.id)})
      |> json_response(200)

    positions = body["data"]["positions"]
    assert length(positions) <= 2000
    assert body["data"]["sampling"]["total"] == 2001
    assert body["data"]["sampling"]["downsampled"]
    assert hd(positions)["date"] == DateTime.to_iso8601(date)
    assert List.last(positions)["date"] == DateTime.to_iso8601(DateTime.add(date, 2000, :second))
  end

  test "charging samples preserve zero power, missing cost and energy units", %{conn: conn} do
    car = history_car()
    date = ~U[2026-09-01 08:00:00.000000Z]
    charge = history_record(TeslaMate.Log.ChargingProcess, car, date)

    TeslaMate.Repo.insert_all(TeslaMate.Log.Charge, [
      %{
        charging_process_id: charge.id,
        date: date,
        battery_level: 80,
        charger_power: 0,
        charge_energy_added: Decimal.new("2.5"),
        ideal_battery_range_km: Decimal.new("300")
      }
    ])

    body =
      conn
      |> get("/api/mobile/v1/charging/#{charge.id}", %{"car_id" => to_string(car.id)})
      |> json_response(200)

    assert body["data"]["cost"] == nil

    assert [%{"charger_power" => 0, "energy_added_kwh" => 2.5, "battery_level" => 80}] =
             body["data"]["samples"]
  end

  defp history_types,
    do: [{"drives", TeslaMate.Log.Drive}, {"charging", TeslaMate.Log.ChargingProcess}]

  defp history_car do
    id = System.unique_integer([:positive])
    {:ok, car} = TeslaMate.Log.create_car(%{eid: id, vid: id, vin: "history-#{id}"})
    car
  end

  defp history_record(schema, car, date) do
    attrs = %{car_id: car.id, start_date: date}

    attrs =
      if schema == TeslaMate.Log.ChargingProcess do
        position =
          TeslaMate.Repo.insert!(%TeslaMate.Log.Position{
            car_id: car.id,
            date: date,
            latitude: Decimal.new("31.2"),
            longitude: Decimal.new("121.5")
          })

        Map.put(attrs, :position_id, position.id)
      else
        attrs
      end

    TeslaMate.Repo.insert!(struct(schema, attrs))
  end
end
