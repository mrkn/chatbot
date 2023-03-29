require "test_helper"
require "utils"

class SlackEventsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SlackTestHelper

  test "app_mention event from known user in known channel" do
    channel_id = conversations(:random).slack_id
    user_id = users(:one).slack_id
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
      timestamp = Time.now.to_i
      params = {
        type: "event_callback",
        event: {
          type: "app_mention",
          text: query,
          channel: channel_id,
          user: user_id
        }
      }
      request_body = ActionDispatch::RequestEncoder.encoder(:json).encode_params(params)
      headers = {
        "X-Slack-Request-Timestamp": timestamp,
        "X-Slack-Signature": compute_request_signature(timestamp, request_body)
      }

      post "/slack/events", params:, headers:, as: :json
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

  test "app_mention event with invalid signature" do
    channel_id = conversations(:random).slack_id
    user_id = users(:one).slack_id
    query_body = "ZZZ"
    query = "<@TEST_BOT_ID> #{query_body}"

    timestamp = Time.now.to_i
    params = {
      type: "event_callback",
      event: {
        type: "app_mention",
        text: query,
        channel: channel_id,
        user: user_id
      }
    }
    headers = {
      "X-Slack-Request-Timestamp": timestamp,
      "X-Slack-Signature": "invalid signature"
    }

    post "/slack/events", params:, headers:, as: :json

    assert_response :bad_request
  end

  test "app_mention event when SLACK_SIGNING_SECRET is not given" do
    channel_id = conversations(:random).slack_id
    user_id = users(:one).slack_id
    query_body = "ZZZ"
    query = "<@TEST_BOT_ID> #{query_body}"

    timestamp = Time.now.to_i
    params = {
      type: "event_callback",
      event: {
        type: "app_mention",
        text: query,
        channel: channel_id,
        user: user_id
      }
    }
    request_body = ActionDispatch::RequestEncoder.encoder(:json).encode_params(params)
    headers = {
      "X-Slack-Request-Timestamp": timestamp,
      "X-Slack-Signature": compute_request_signature(timestamp, request_body)
    }

    with_env("SLACK_SIGNING_SECRET" => nil) do
      assert_nil ENV["SLACK_SIGNING_SECRET"]
      stub(Slack::Events.config).signing_secret { nil }

      post "/slack/events", params:, headers:, as: :json
    end

    assert_response :internal_server_error
  end
end
