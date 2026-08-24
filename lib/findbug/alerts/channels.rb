module Findbug
  module Alerts
    module Channels
    end
  end
end

require_relative "./channels/base"
require_relative "./channels/discord"
require_relative "./channels/email"
require_relative "./channels/slack"
require_relative "./channels/webhook"
