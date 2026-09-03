defmodule TeslaMateWeb.Plugs.MobileApiAuth do
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    expected = Application.get_env(:teslamate, :mobile_api_token)

    with token when is_binary(token) and byte_size(token) >= 32 <- expected,
         ["Bearer " <> supplied] <- get_req_header(conn, "authorization"),
         true <- secure_compare(token, supplied) do
      conn
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_compare(_, _), do: false
end
