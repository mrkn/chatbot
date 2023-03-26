require "test_helper"
require "slack_bot/utils"

class TestSlackBot < ActiveSupport::TestCase
  {
    "gpt-4" => 0.03r/1000,
    "gpt-4-0314" => 0.03r/1000,
    "gpt-3.5-turbo" => 0.002r/1000,
    "gpt-3.5-turbo-0301" => 0.002r/1000
  }.each do |model, unit_price|
    test "SlackBot.prompt_unit_price(#{model.inspect})" do
      assert_equal unit_price, SlackBot.prompt_unit_price(model)
    end
  end

  {
    "gpt-4" => 0.06r/1000,
    "gpt-4-0314" => 0.06r/1000,
    "gpt-3.5-turbo" => 0.002r/1000,
    "gpt-3.5-turbo-0301" => 0.002r/1000
  }.each do |model, unit_price|
    test "SlackBot.completion_unit_price(#{model.inspect})" do
      assert_equal unit_price, SlackBot.completion_unit_price(model)
    end
  end
end
