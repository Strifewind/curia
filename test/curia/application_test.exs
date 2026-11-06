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

  test "firmware VM keeps running after Elixir CLI startup and enables the startup guard" do
    vm_args =
      Path.expand("../../rel/vm.args.eex", __DIR__)
      |> EEx.eval_file()
      |> String.split()

    {erlang_args, ["-extra" | elixir_args]} = Enum.split_while(vm_args, &(&1 != "-extra"))
    erlang_options = Enum.chunk_every(erlang_args, 3, 1, :discard)

    assert "--no-halt" in elixir_args
    assert "-heart" in erlang_args
    assert ["-env", "HEART_INIT_TIMEOUT", "600"] in erlang_options
    assert ["-env", "HEART_BEAT_TIMEOUT", "30"] in erlang_options
  end

  defp restore_env(app, key, nil), do: Elixir.Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Elixir.Application.put_env(app, key, value)
end
