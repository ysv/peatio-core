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
        EM.run {
          orderbooks = ::Peatio::Upstream::Binance.run!(
            markets: ["ethbtc"],
          )

          logger = Peatio::Upstream::Binance.logger

          EM::PeriodicTimer.new(5) do
            orderbooks.each do |symbol, orderbook|
              asks, bids = orderbook.depth(5)

              asks.each do |(price, volume)|
                logger.info "[#{symbol}] ASK #{price} #{volume}"
              end

              bids.each do |(price, volume)|
                logger.info "[#{symbol}] BID #{price} #{volume}"
              end
            end
          end
        }
      end
    end

    subcommand "ranger", "Start ranger process", Ranger
    subcommand "upstream", "Start upstream binance process", UpstreamBinance
  end

  class Root < Peatio::Command::Base
    subcommand "start", "Start a service", Start
  end
end
