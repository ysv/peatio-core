# frozen_string_literal: true

module Peatio::Command::Service

  class Start < Peatio::Command::Base
    class Ranger < Peatio::Command::Base
      def execute
        ::Peatio::Ranger.run!
      end
    end

    class UpstreamBinance < Peatio::Command::Base
      def execute
        ::Peatio::Upstream::Binance.run!(
          markets: ["ethbtc"]
        )
      end
    end

    subcommand "ranger", "Start ranger process", Ranger
    subcommand "upstream", "Start upstream binance process", UpstreamBinance
  end

  class Root < Peatio::Command::Base
    subcommand "start", "Start a service", Start
  end

end
