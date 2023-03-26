require "test_helper"
require "utils"

class SlackEventsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SlackTestHelper

  test "app_mention event" do
    channel_id = "XXX"
    user_id = "YYY"
    query_body = "ZZZ"
    query = "<@TEST_BOT_ID> #{query_body}"
    answer = "ABC"
    expected_response = "<@#{user_id}> #{answer}"

    stub(Utils).chat_completion({
      role: "user",
      content: [
        "You are ChatGPT, a large language model trained by OpenAI.",
        "Answer as concisely as possible.",
        "Current date: #{Time.now.strftime("%Y-%m-%d")}",
        "\n",
        "ZZZ"
      ].join("\n")
    }) do
      {
        "model" => "gpt-3.5-turbo-0301",
        "usage" => {
          "prompt_tokens" => 70,
          "completion_tokens" => 50,
          "total_tokens" => 120
        },
        "choices" => [{"message" => {"content" => answer}}]
      }
    end

    stub_request(:post, "https://slack.com/api/chat.postMessage")

    assert_enqueued_with(job: ChatCompletionJob) do
      post "/slack/events",
           params: {
             type: "event_callback",
             event: {
               type: "app_mention",
               text: query,
               channel: channel_id,
               user: user_id
             }
           },
           as: :json
    end

    perform_enqueued_jobs

    assert_response :success

    actual_body = nil
    assert_requested(
      :post, "https://slack.com/api/chat.postMessage",
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded"
      }
    ) do |request|
      actual_body = decode_slack_client_request_body(request.body)
    end

    assert_equal(
      {
        "channel" => channel_id,
        "text" => expected_response,
        "blocks" => [
          {
            "type" => "section",
            "text" => {
              "type" => "mrkdwn",
              "text" => expected_response
            }
          },
          api_usage_block(70, 50, "gpt-3.5-turbo-0301"),
          feedback_action_block
        ]
      },
      actual_body
    )
  end
end
