require "test_helper"

class Provider::Snaptrade2Test < ActiveSupport::TestCase
  setup do
    @item = SnaptradeItem.new(
      family: families(:dylan_family), name: "API test", client_id: "client",
      consumer_key: "consumer", snaptrade_user_id: "user +/@",
      snaptrade_user_secret: "private&secret"
    )
    @provider = Provider::Snaptrade2.new(@item)
    @requests = []
  end

  test "signs the transmitted query without OAuth and signs portal POST content" do
    use_responses([ [] ], method: :get)
    assert_equal [], @provider.list_accounts
    request = @requests.first
    assert_equal "private&secret", Rack::Utils.parse_query(request.url.query)["userSecret"]
    assert_nil request.request_headers["Authorization"]
    assert_signature(request, nil)

    use_responses([ { redirectURI: "https://app.snaptrade.com/connect" } ], method: :post)
    assert_equal "https://app.snaptrade.com/connect", @provider.get_connection_url(redirect_url: "http://localhost:3000/callback")
    request = @requests.last
    assert_equal "read", JSON.parse(request.body)["connectionType"]
    assert_signature(request, JSON.parse(request.body))
  end

  test "fetches every activity page and retains provider fields" do
    first_page = Array.new(1000) { |index| { id: index.to_s } }
    use_responses([ { data: first_page }, { data: [ { id: "1000", amount: 7 } ] } ])
    result = @provider.get_account_activities(account_id: "account", start_date: Date.new(2025, 1, 1))
    assert_equal 1001, result["data"].size
    assert_equal "1000", result["data"].last["id"]
    assert_equal 7, result["data"].last["amount"]
    assert_equal %w[0 1000], @requests.map { |r| Rack::Utils.parse_query(r.url.query)["offset"] }
    assert_equal "2025-01-01", Rack::Utils.parse_query(@requests.first.url.query)["startDate"]
  end

  test "invalid responses do not become an empty account or activity snapshot" do
    use_responses([ {}, [ {} ] ])
    2.times { assert_raises(Provider::Snaptrade::ApiError) { @provider.list_accounts } }
    use_responses([ {} ])
    assert_raises(Provider::Snaptrade::ApiError) { @provider.get_account_activities(account_id: "account") }
  end

  test "authentication and transport errors never disclose credentials or response bodies" do
    use_responses([ { error: "private&secret" } ], status: 401)
    error = assert_raises(Provider::Snaptrade::AuthenticationError) { @provider.list_accounts }
    refute_includes error.message, "private&secret"

    connection = mock
    connection.expects(:post).raises(Faraday::TimeoutError, "https://example.com?userSecret=private&secret").once
    @provider.stubs(:api_connection).returns(connection)
    error = assert_raises(Provider::Snaptrade::ApiError) { @provider.get_connection_url(redirect_url: "http://localhost:3000") }
    refute_includes error.message, "private&secret"
    assert_nil error.cause
  end

  test "API credentials select the new provider and participate in family sync without OAuth configuration" do
    @item.save!
    assert_includes SnaptradeItem.syncable, @item
    assert_instance_of Provider::Snaptrade2, @item.snaptrade_provider
    Provider::Snaptrade.stubs(:oauth_configured?).returns(false)
    assert_instance_of Provider::Snaptrade2, Provider::SnaptradeAdapter.build_provider(family: @item.family)
    assert @item.fully_configured?
    assert_not @item.oauth_configured?
    assert_includes SnaptradeItem.api_connections, @item
    assert_not_includes SnaptradeItem.oauth_connections, @item
    @item.update!(scheduled_for_deletion: true)
    assert_not_includes SnaptradeItem.syncable, @item
  end

  test "local account cleanup leaves shared API brokerage connections intact" do
    @item.save!
    Provider::Snaptrade2.any_instance.expects(:delete_connection).never
    SnaptradeConnectionCleanupJob.perform_now(snaptrade_item_id: @item.id, authorization_id: "auth", account_id: "old")
  end

  test "API item sync reaches the existing importer without an OAuth token" do
    @item.save!
    @item.expects(:import_latest_snaptrade_data).with(sync: nil)
    SnaptradeItem::Syncer.new(@item).perform_sync(nil)
  end

  private

    def use_responses(payloads, method: :get, status: 200)
      stubs = Faraday::Adapter::Test::Stubs.new
      payloads.each do |payload|
        stubs.public_send(method, /./) do |env|
          @requests << env.dup
          [ status, { "Content-Type" => "application/json" }, payload.to_json ]
        end
      end
      connection = Faraday.new { |f| f.adapter :test, stubs }
      @provider.stubs(:api_connection).returns(connection)
    end

    def assert_signature(request, content)
      payload = JSON.generate({ "content" => content, "path" => request.url.path, "query" => request.url.query })
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "consumer", payload))
      assert_equal expected, request.request_headers["Signature"]
    end
end
