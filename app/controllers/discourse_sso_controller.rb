require 'discourse/single_sign_on'

class DiscourseSsoController < ApplicationController
  include SharedHelper
  include DiscourseHelper

  before_filter :require_config

  def login
    if require_activation?
      redirect_to discourse_url
    else
      redirect_to discourse_login_url
    end
  end

  def sso
    if spree_current_user
      begin
        redirect_to sso_url
      rescue TypeError
        render text: "Bad SingleSignOn request.", status: :bad_request
      end
    else
      redirect_to login_path
    end
  end

  private

  def sso_url
    secret = discourse_sso_secret!
    discourse_url = discourse_url!
    sso = Discourse::SingleSignOn.parse(request.query_string, secret)
    sso.email = spree_current_user.email
    sso.username = spree_current_user.login
    sso.external_id = spree_current_user.id
    sso.sso_secret = secret
    sso.admin = admin_user?
    sso.require_activation = require_activation?
    sso.to_url(discourse_sso_url)
  end

  def require_config
    raise ActionController::RoutingError.new('Not Found') unless discourse_configured?
  end

  def require_activation?
    !admin_user? && !email_validated?
  end

  def email_validated?
    spree_current_user.enterprises.confirmed.map(&:email).include?(spree_current_user.email)
  end
end
