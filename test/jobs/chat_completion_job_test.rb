require "test_helper"

class ChatCompletionJobTest < ActiveJob::TestCase
  include SlackTestHelper

  test "normal case" do
    message = messages(:one)
    channel = message.conversation
    user = message.user
    answer = "ABC"
    expected_response = "<@#{user.slack_id}> #{answer}"

    stub_request(:post, "https://slack.com/api/chat.postMessage")

    mock(Utils).chat_completion(
      {
        role: "user",
        content: [
          "You are ChatGPT, a large language model trained by OpenAI.",
          "Answer as concisely as possible.",
          "Current date: #{Time.now.strftime("%Y-%m-%d")}",
          "\n",
          message.text
        ].join("\n")
      },
      model: "gpt-3.5-turbo",
      temperature: 0.7
    ) do
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

    ChatCompletionJob.perform_now("message_id" => message.id)

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
        "channel" => channel.slack_id,
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
        ],
        "thread_ts" => message.slack_thread_ts
      },
      actual_body
    )
  end
end
