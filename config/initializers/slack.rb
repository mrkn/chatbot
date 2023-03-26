require "slack-ruby-client"

Slack.configure do |config|
  config.token = ENV.fetch("SLACK_BOT_TOKEN", "SLACK_TOKEN_IS_NOT_GIVEN")
end
