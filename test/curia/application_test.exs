defmodule Curia.ApplicationTest do
  use ExUnit.Case, async: false

  alias Curia.Application, as: CuriaApplication

  setup do
    previous_target = Elixir.Application.get_env(:curia, :target)
    previous_network_config = Elixir.Application.get_env(:vintage_net, :config)

    on_exit(fn ->
      restore_env(:curia, :target, previous_target)
      restore_env(:vintage_net, :config, previous_network_config)
    end)

    :ok
  end

  test "validates the target USB gadget configuration" do
    Elixir.Application.put_env(:curia, :target, true)
    Elixir.Application.put_env(:vintage_net, :config, [{"usb0", %{type: VintageNetDirect}}])

    assert :ok = CuriaApplication.validate_firmware_config!()
  end

  test "rejects target firmware without VintageNetDirect on usb0" do
    Elixir.Application.put_env(:curia, :target, true)
    Elixir.Application.put_env(:vintage_net, :config, [{"usb0", %{ipv4: %{method: :dhcp}}}])

    assert_raise RuntimeError, "Target firmware requires usb0 to use VintageNetDirect", fn ->
      CuriaApplication.validate_firmware_config!()
    end
  end

  defp restore_env(app, key, nil), do: Elixir.Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Elixir.Application.put_env(app, key, value)
end
