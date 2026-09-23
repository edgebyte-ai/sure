# SnapTrade partner API authentication, compatible with snaptrade-python-sdk.
# Reuse SnapTrade's data contract; only authentication and activity pagination differ.
class Provider::Snaptrade2 < Provider::Snaptrade
  PAGE_SIZE = 1000

  def list_accounts
    accounts = super
    unless accounts.is_a?(Array) && accounts.all? { |account| account.is_a?(Hash) && account["id"].present? }
      raise ApiError, "SnapTrade API returned an invalid accounts list"
    end
    accounts
  end

  def get_account_activities(account_id:, start_date: nil, end_date: nil)
    params = { limit: PAGE_SIZE, offset: 0 }
    params[:startDate] = start_date.to_date.to_s if start_date
    params[:endDate] = end_date.to_date.to_s if end_date
    activities = []
    loop do
      response = get_json("/api/v1/accounts/#{account_id}/activities", params)
      page = response.is_a?(Hash) ? response["data"] : response
      raise ApiError, "SnapTrade API returned invalid activities" unless page.is_a?(Array)

      activities.concat(page)
      break if page.size < PAGE_SIZE

      params[:offset] += page.size
    end
    { "data" => activities }
  end

  private

    def request_json(method, path, params: {}, body: nil, **)
      raise ConfigurationError, "SnapTrade API credentials are incomplete" unless snaptrade_item.api_configured?

      attempts = 0
      begin
        # Sign the exact encoded query that Faraday sends, including userSecret.
        query = Faraday::Utils.build_query(params.merge(
          userId: snaptrade_item.snaptrade_user_id,
          userSecret: snaptrade_item.snaptrade_user_secret,
          clientId: snaptrade_item.client_id,
          timestamp: Time.now.to_i
        ))
        content = body&.stringify_keys&.sort&.to_h
        signature_payload = JSON.generate({ content: content, path: path, query: query }, ascii_only: true)
        signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", snaptrade_item.consumer_key, signature_payload))
        response = api_connection.public_send(method, "#{API_BASE_URL}#{path}?#{query}") do |request|
          request.headers["Signature"] = signature
          request.headers["Accept"] = "application/json"
          if body
            request.headers["Content-Type"] = "application/json"
            request.body = JSON.generate(content)
          end
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Errno::ECONNRESET, Errno::ETIMEDOUT
        attempts += 1
        if method == :get && attempts <= MAX_RETRIES
          sleep(calculate_retry_delay(attempts))
          retry
        end
        # Transport exceptions can contain the URL (and therefore userSecret).
        raise ApiError, "SnapTrade API network request failed", cause: nil
      end

      if response.success?
        return {} if response.body.blank?
        return JSON.parse(response.body)
      end

      DebugLogEntry.capture(
        category: "provider_sync", level: :error,
        message: "SnapTrade API request failed (HTTP #{response.status})",
        source: "Provider::Snaptrade2", provider_key: "snaptrade2",
        family: snaptrade_item.family,
        metadata: { snaptrade_item_id: snaptrade_item.id, status: response.status }
      )
      if [ 401, 403 ].include?(response.status)
        snaptrade_item.update!(status: :requires_update) if snaptrade_item.persisted?
        raise AuthenticationError, "SnapTrade API authentication failed (HTTP #{response.status})"
      end
      raise ApiError.new("SnapTrade API request failed (HTTP #{response.status})", status_code: response.status)
    rescue JSON::ParserError
      raise ApiError, "SnapTrade API returned invalid JSON", cause: nil
    end
end
