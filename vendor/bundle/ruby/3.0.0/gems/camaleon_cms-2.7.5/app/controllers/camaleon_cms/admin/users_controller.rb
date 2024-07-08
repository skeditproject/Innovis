module CamaleonCms
  module Admin
    class UsersController < CamaleonCms::AdminController
      before_action :validate_role, except: %i[profile profile_edit]
      add_breadcrumb I18n.t('camaleon_cms.admin.sidebar.users'), :cama_admin_users_url
      before_action :set_user, only: %i[show edit update destroy impersonate]

      def index
        add_breadcrumb I18n.t('camaleon_cms.admin.users.list_users')
        @users = current_site.users.paginate(page: params[:page], per_page: current_site.admin_per_page)
      end

      def profile
        add_breadcrumb I18n.t('camaleon_cms.admin.users.profile')
        @user = params[:user_id].present? ? current_site.the_user(params[:user_id].to_i).object : cama_current_user.object
        edit
      end

      def profile_edit
        add_breadcrumb I18n.t('camaleon_cms.admin.users.profile')
        @user = cama_current_user.object
        edit
      end

      def show
        add_breadcrumb I18n.t('camaleon_cms.admin.users.profile')
        render 'profile'
      end

      def update
        r = { user: @user }
        hooks_run('user_update', r)
        if @user.update(user_params)
          @user.set_metas(params[:meta]) if params[:meta].present?
          @user.set_field_values(params[:field_options])
          r = { user: @user, message: t('camaleon_cms.admin.users.message.updated'), params: params }
          hooks_run('user_after_edited', r)
          flash[:notice] = r[:message]
          r = { user: @user }
          hooks_run('user_updated', r)
          if cama_current_user.id == @user.id
            redirect_to action: :profile_edit
          else
            redirect_to action: :index
          end
        else
          render 'form'
        end
      end

      # update some ajax requests from profile or user form
      def updated_ajax
        @user = current_site.users.find(params[:user_id])
        update_session = current_user_is?(@user)
        @user.update(params.require(:password).permit!)
        render inline: @user.errors.full_messages.join(', ')
        # keep user logged in when changing their own password
        update_auth_token_in_cookie @user.auth_token if update_session && @user.saved_change_to_password_digest?
      end

      def update_auth_token_in_cookie(token)
        return unless cookie_auth_token_complete?

        current_token = cookie_split_auth_token
        updated_token = [token, *current_token[1..]]
        cookies[:auth_token] = updated_token.join('&')
      end

      def current_user_is?(user)
        user_auth_token_from_cookie == user.auth_token
      rescue StandardError
        false
      end

      def edit
        add_breadcrumb I18n.t('camaleon_cms.admin.button.edit')
        r = { user: @user, render: 'form' }
        hooks_run('user_edit', r)
        render r[:render]
      end

      def new
        @user ||= current_site.users.new
        add_breadcrumb I18n.t('camaleon_cms.admin.button.new')
        r = { user: @user, render: 'form' }
        hooks_run('user_new', r)
        render r[:render]
      end

      def create
        user_data = params.require(:user).permit!
        @user = current_site.users.new(user_data)
        r = { user: @user }
        hooks_run('user_create', r)
        if @user.save
          @user.set_metas(params[:meta]) if params[:meta].present?
          @user.set_field_values(params[:field_options])
          r = { user: @user }
          hooks_run('user_created', r)
          flash[:notice] = t('camaleon_cms.admin.users.message.created')
          redirect_to action: :index
        else
          new
        end
      end

      def destroy
        if cama_current_user.id == @user.id
          flash[:error] =
            t('camaleon_cms.admin.users.message.user_can_not_delete_own_account',
              default: 'User can not delete own account')
        elsif @user.destroy
          flash[:notice] = t('camaleon_cms.admin.users.message.deleted')
          r = { user: @user }
          hooks_run('user_destroyed', r)
        end
        redirect_to action: :index
      end

      def impersonate
        authorize! :impersonate, @user
        session_switch_user(@user, cama_admin_dashboard_path)
      end

      private

      def validate_role
        (user_id_param.present? && cama_current_user.id.to_s == user_id_param) || authorize!(:manage, :users)
      end

      def user_id_param
        params[:id] || params[:user_id]
      end

      def user_params
        parameters = params.require(:user)
        if cama_current_user.role_grantor?(@user)
          parameters.permit(:username, :email, :role, :first_name, :last_name)
        else
          parameters.permit(:username, :email, :first_name, :last_name)
        end
      end

      def set_user
        @user = current_site.users.find(user_id_param)
      rescue StandardError
        flash[:error] = t('camaleon_cms.admin.users.message.error')
        redirect_to cama_admin_path
      end
    end
  end
end
