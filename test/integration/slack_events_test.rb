require "test_helper"
require "utils"

class SlackEventsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SlackTestHelper

  test "app_mention event from known user in known channel" do
    slack_ts = Time.now.to_f.to_s
    channel = conversations(:random)
    user = users(:one)
    query_body = "ZZZ"
    query = "<@TEST_BOT_ID> #{query_body}"
    answer = "ABC"
    expected_response = "<@#{user.slack_id}> #{answer}"

    chat_completion_messages = [
      {
        role: "user",
        content: [
          "You are ChatGPT, a large language model trained by OpenAI.",
          "Answer as concisely as possible.",
          "Current date: #{Time.now.strftime("%Y-%m-%d")}",
          "\n",
          "ZZZ"
        ].join("\n")
      }
    ]

    chat_completion_response = {
      "model" => "gpt-3.5-turbo-0301",
      "usage" => {
        "prompt_tokens" => 70,
        "completion_tokens" => 50,
        "total_tokens" => 120
      },
      "choices" => [{"message" => {"content" => answer}}]
    }

    stub(Utils).chat_completion(
      *chat_completion_messages,
      model: "gpt-3.5-turbo",
      temperature: 0.7
    ) { chat_completion_response }

    stub_request(:post, "https://slack.com/api/chat.postMessage")

    assert Message.find_by(conversation: channel, user: user, slack_ts: slack_ts).blank?

    assert_enqueued_with(job: ChatCompletionJob) do
      params = {
        type: "event_callback",
        event: {
          type: "app_mention",
          text: query,
          channel: channel.slack_id,
          user: user.slack_id,
          ts: slack_ts
        }
      }
      request_body = ActionDispatch::RequestEncoder.encoder(:json).encode_params(params)
      timestamp = slack_ts.to_i
      headers = {
        "X-Slack-Request-Timestamp": timestamp,
        "X-Slack-Signature": compute_request_signature(timestamp, request_body)
      }

      post "/slack/events", params:, headers:, as: :json
    end

    message = Message.find_by!(conversation: channel, user: user, slack_ts: slack_ts)
    assert_equal([
                   query_body,
                   slack_ts,
                 ],
                 [
                   message.text,
                   message.slack_thread_ts,
                 ])

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

    query = Query.find_by!(message: message)
    response = Response.find_by!(query: query)

    assert_equal(
      {
        "channel" => channel.slack_id,
        "text" => expected_response,
        "thread_ts" => slack_ts,
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


  test "app_mention event from unknown user in unknown channel" do
    slack_ts = Time.now.to_f.to_s
    channel_id = "CUQF0FE2V"
    user_id = "U039NG1FNJE"
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

    stub_request(:post, "https://slack.com/api/users.info")
      .with(body: {"user" => user_id, "include_locale" => true},
            headers: {"Content-Type" => "application/x-www-form-urlencoded"})
      .to_return(
        body: {
          "ok" => true,
          "user" => {
            "id" => user_id,
            "name" => "mrkn",
            "real_name" => "Kenta Murata",
            "tz_offset" => 3600,
            "profile" => {
              "email" => "mrkn@example.com"
            },
            "locale" => "en-UK"
          }
        }.to_json
      )

    stub_request(:post, "https://slack.com/api/conversations.info")
      .with(body: "channel=#{channel_id}",
            headers: {"Content-Type" => "application/x-www-form-urlencoded"})
      .to_return(
        body: {
          "ok" => true,
          "channel" => {
            "id" => channel_id,
            "name" => "unknown-channel",
          }
        }.to_json
      )

    assert User.find_by_slack_id(user_id).blank?
    assert Conversation.find_by_slack_id(channel_id).blank?

    assert_enqueued_with(job: ChatCompletionJob) do
      timestamp = Time.now.to_i
      params = {
        type: "event_callback",
        event: {
          type: "app_mention",
          text: query,
          channel: channel_id,
          user: user_id,
          ts: slack_ts
        }
      }
      request_body = ActionDispatch::RequestEncoder.encoder(:json).encode_params(params)
      timestamp = slack_ts.to_i
      headers = {
        "X-Slack-Request-Timestamp": timestamp,
        "X-Slack-Signature": compute_request_signature(timestamp, request_body)
      }

      post "/slack/events", params:, headers:, as: :json
    end

    new_user = User.find_by_slack_id(user_id)
    assert_equal(["mrkn", "Kenta Murata", "mrkn@example.com", 3600, "en-UK"],
                 [
                   new_user.name,
                   new_user.real_name,
                   new_user.email,
                   new_user.tz_offset,
                   new_user.locale
                 ])

    new_channel = Conversation.find_by_slack_id(channel_id)
    assert_equal("unknown-channel", new_channel.name)

    assert new_channel.members.include?(new_user)
  end


  test "app_mention event with invalid signature" do
    slack_ts = Time.now.to_f.to_s
    channel_id = conversations(:random).slack_id
    user_id = users(:one).slack_id
    query_body = "ZZZ"
    query = "<@TEST_BOT_ID> #{query_body}"

    params = {
      type: "event_callback",
      event: {
        type: "app_mention",
        text: query,
        channel: channel_id,
        user: user_id,
        ts: slack_ts
      }
    }
    headers = {
      "X-Slack-Request-Timestamp": slack_ts.to_i,
      "X-Slack-Signature": "invalid signature"
    }

    post "/slack/events", params:, headers:, as: :json

    assert_response :bad_request
  end


  test "app_mention event when SLACK_SIGNING_SECRET is not given" do
    slack_ts = Time.now.to_f.to_s
    channel_id = conversations(:random).slack_id
    user_id = users(:one).slack_id
    query_body = "ZZZ"
    query = "<@TEST_BOT_ID> #{query_body}"

    params = {
      type: "event_callback",
      event: {
        type: "app_mention",
        text: query,
        channel: channel_id,
        user: user_id,
        ts: slack_ts
      }
    }
    request_body = ActionDispatch::RequestEncoder.encoder(:json).encode_params(params)
    timestamp = slack_ts.to_i
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


  test "app_mention event in channel where not allowed" do
    skip "TODO"
  end


  test "app_mention event with thread_ts in channel where thread conversation is not allowed" do
    skip "TODO"
  end
end
