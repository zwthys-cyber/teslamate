defmodule TeslaMateWeb.MobileApiController do
  use TeslaMateWeb, :controller

  alias TeslaMate.{Log, Vehicles}

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

  defp json_value(%Decimal{} = value), do: Decimal.to_float(value)
  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(value) when is_boolean(value) or is_nil(value), do: value
  defp json_value(:unknown), do: nil
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value), do: value
end
