defmodule CloudIServiceDbRiak do
  use Mix.Project

  def project do
    [app: :cloudi_service_db_riak,
     version: "1.4.0",
     language: :erlang,
     description: description,
     package: package,
     deps: deps]
  end

  defp deps do
    [# TODO, riakc has trouble with 17.x types
     {:riakc,
      [git: "https://github.com/basho/riak-erlang-client.git",
       tag: "1.4.2"]},
     # protobuffs rebar.config version which doesn't work with 17.x types
     {:meck, "~> 0.8.2", override: true}, # due to protobuffs
     {:cloudi_core, "~> 1.4.0"}]
  end

  defp description do
    "Erlang/Elixir Cloud Framework Riak Service"
  end

  defp package do
    [files: ~w(src doc test rebar.config README.markdown),
     contributors: ["Michael Truog"],
     licenses: ["BSD"],
     links: %{"Website" => "http://cloudi.org",
              "GitHub" => "https://github.com/CloudI/" <>
                          "cloudi_service_db_riak"}]
   end
end
