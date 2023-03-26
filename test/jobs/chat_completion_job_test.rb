require "test_helper"

class ChatCompletionJobTest < ActiveJob::TestCase
  include SlackTestHelper

  test "normal case" do
    channel_id = "XXX"
    user_id = "YYY"
    query = "ZZZ"
    answer = "ABC"
    expected_response = "<@#{user_id}> #{answer}"

    stub_request(:post, "https://slack.com/api/chat.postMessage")

    mock(Utils).chat_completion({
      role: "user",
      content: [
        "You are ChatGPT, a large language model trained by OpenAI.",
        "Answer as concisely as possible.",
        "Current date: #{Time.now.strftime("%Y-%m-%d")}",
        "\n",
        query
      ].join("\n")
    }) do
      {
        "model" => "gpt-3.5-turbo-0301",
        "usage" => {
          "prompt_tokens" => 70,
          "completion_tokens" => 50,
          "total_tokens" => 120
        },
        "choices" => [
          {
            "message" => {"content" => answer}
          }
        ]
      }
    end

    ChatCompletionJob.perform_now({
      "channel" => channel_id,
      "user" => user_id,
      "message" => query
    })

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
