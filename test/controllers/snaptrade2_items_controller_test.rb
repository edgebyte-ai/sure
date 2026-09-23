require "test_helper"

class Snaptrade2ItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @credentials = { client_id: "api-client", consumer_key: "api-secret", snaptrade_user_id: "api-user", snaptrade_user_secret: "user-secret" }
    SnaptradeItem.stubs(:encryption_ready?).returns(true)
    SnaptradeItem.any_instance.stubs(:sync_later_with_follow_up)
  end

  test "creates an API connection without OAuth and routes to account setup" do
    Provider::Snaptrade2.any_instance.expects(:list_accounts).returns([])
    assert_difference "SnaptradeItem.count", 1 do
      post snaptrade2_items_path, params: { snaptrade_item: @credentials }
    end
    item = users(:family_admin).family.snaptrade_items.api_connections.first
    assert_redirected_to setup_accounts_snaptrade_item_path(item)
    assert_nil item.oauth_access_token
    assert_instance_of Provider::Snaptrade2, item.snaptrade_provider
  end

  test "failed authentication and incomplete credentials do not save a connection" do
    Provider::Snaptrade2.any_instance.expects(:list_accounts).raises(Provider::Snaptrade::AuthenticationError, "secret upstream details")
    assert_no_difference "SnaptradeItem.count" do
      post snaptrade2_items_path, params: { snaptrade_item: @credentials }
      post snaptrade2_items_path, params: { snaptrade_item: @credentials.except(:consumer_key) }
    end
    refute_includes flash[:alert], "secret upstream details"
  end

  test "requires encryption and rejects non-admin writes" do
    SnaptradeItem.stubs(:encryption_ready?).returns(false)
    Provider::Snaptrade2.any_instance.expects(:list_accounts).never
    assert_no_difference "SnaptradeItem.count" do
      post snaptrade2_items_path, params: { snaptrade_item: @credentials }
    end
    assert_equal I18n.t("snaptrade2.encryption_required"), flash[:alert]
    sign_in users(:family_member)
    assert_no_difference "SnaptradeItem.count" do
      post snaptrade2_items_path, params: { snaptrade_item: @credentials }
    end
    assert_redirected_to accounts_path
  end

  test "update is family scoped and cannot overwrite an OAuth connection" do
    oauth_item = snaptrade_items(:configured_item)
    patch snaptrade2_item_path(oauth_item), params: { snaptrade_item: @credentials }
    assert_response :not_found
    foreign_item = SnaptradeItem.create!(@credentials.merge(name: "Other", family: families(:empty)))
    patch snaptrade2_item_path(foreign_item), params: { snaptrade_item: @credentials }
    assert_response :not_found
  end

  test "blank update fields preserve secrets and form never returns stored credentials" do
    item = SnaptradeItem.create!(@credentials.merge(name: "API", family: users(:family_admin).family))
    Provider::Snaptrade2.any_instance.expects(:list_accounts).returns([])
    patch snaptrade2_item_path(item), params: { snaptrade_item: @credentials.transform_values { "" } }
    assert_redirected_to setup_accounts_snaptrade_item_path(item)
    assert_equal "api-secret", item.reload.consumer_key
    get connect_form_settings_providers_path(provider_key: "snaptrade2")
    assert_response :success
    refute_includes response.body, "api-secret"
    refute_includes response.body, "user-secret"
    assert_select "input[name='snaptrade_item[consumer_key]'][type='password'][value='']"
  end
end
