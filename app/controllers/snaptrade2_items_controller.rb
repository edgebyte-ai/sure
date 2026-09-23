class Snaptrade2ItemsController < ApplicationController
  before_action :require_admin!

  def create
    save_connection(Current.family.snaptrade_items.new(name: "SnapTrade API"))
  end

  def update
    save_connection(Current.family.snaptrade_items.active.api_connections.find(params[:id]))
  end

  private

    def save_connection(item)
      unless SnaptradeItem.encryption_ready?
        return redirect_to settings_providers_path, alert: t("snaptrade2.encryption_required")
      end

      attributes = params.require(:snaptrade_item)
        .permit(:client_id, :consumer_key, :snaptrade_user_id, :snaptrade_user_secret)
        .to_h.transform_values { |value| value.to_s.strip }.reject { |_, value| value.blank? }

      # A different SnapTrade identity belongs in a new connection, not over existing accounts.
      if item.persisted? && %w[client_id snaptrade_user_id].any? { |key| attributes.key?(key) && attributes[key] != item.public_send(key) }
        return redirect_to settings_providers_path, alert: t("snaptrade2.identity_changed")
      end

      item.assign_attributes(attributes)
      unless item.api_configured?
        return redirect_to settings_providers_path, alert: t("snaptrade2.missing_credentials")
      end

      Provider::Snaptrade2.new(item).list_accounts
      item.status = :good
      item.save!
      item.sync_later_with_follow_up
      redirect_to setup_accounts_snaptrade_item_path(item), notice: t("snaptrade2.saved")
    rescue Provider::Snaptrade::Error
      redirect_to settings_providers_path, alert: t("snaptrade2.connection_failed")
    end
end
