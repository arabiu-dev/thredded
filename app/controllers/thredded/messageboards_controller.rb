# frozen_string_literal: true

module Thredded
  class MessageboardsController < Thredded::ApplicationController
    before_action :thredded_require_login!, only: %i[new create edit update destroy]

    after_action :verify_authorized, except: %i[index]
    after_action :verify_policy_scoped, except: %i[new create edit update destroy]

    def index
      # Scoped messageboards for regular usage
      scoped_messageboards = policy_scope(Thredded::Messageboard.all)
    
      respond_to do |format|
        format.html do
          # For HTML response, use scoped and grouped messageboards
          @groups = Thredded::MessageboardGroupView.grouped(
            scoped_messageboards,
            user: thredded_current_user
          )
        end
    
        format.json do
          if params[:mg].present?
            # If 'ss' query parameter is present, return all messageboards just by their names
            # Fetch all messageboards without any scope
            all_messageboards = Thredded::Messageboard.all
            render json: all_messageboards.as_json(only: [:name, :slug, :id])
          else
            # Otherwise, return structured, scoped and grouped messageboards
            all_groups = Thredded::MessageboardGroup.order(:position, :id).to_a
            ungrouped_messageboards = scoped_messageboards.where(messageboard_group_id: nil)
    
            # Optionally create a default group for ungrouped messageboards if there are any
            groups = Thredded::MessageboardGroupView.grouped(scoped_messageboards, user: thredded_current_user)
            unless ungrouped_messageboards.empty?
              default_group = Thredded::MessageboardGroup.new(id: nil, name: "General Discussion", emoji: "🗨️")
              groups += [Thredded::MessageboardGroupView.new(default_group, ungrouped_messageboards)]
            end
    
            render json: { groups: groups.map(&:as_json) }
          end
        end
      end
    end
    

    def new
      @new_messageboard = Thredded::Messageboard.new
      authorize_creating @new_messageboard
    end

    def create
      @new_messageboard = Thredded::Messageboard.new(messageboard_params)
      authorize_creating @new_messageboard
      if Thredded::CreateMessageboard.new(@new_messageboard, thredded_current_user).run
        redirect_to root_path
      else
        render :new
      end
    end

    def edit
      @messageboard = Thredded::Messageboard.friendly_find!(params[:id])
      authorize @messageboard, :update?
    end

    def update
      @messageboard = Thredded::Messageboard.friendly_find!(params[:id])
      authorize @messageboard, :update?
      if @messageboard.update(messageboard_params)
        redirect_to messageboard_topics_path(@messageboard), notice: I18n.t('thredded.messageboard.updated_notice')
      else
        render :edit
      end
    end

    def destroy
      @messageboard = Thredded::Messageboard.friendly_find!(params[:id])
      authorize @messageboard, :destroy?
      @messageboard.destroy!
      redirect_to root_path, notice: t('thredded.messageboard.deleted_notice')
    end

    private

    def messageboard_params
      params
        .require(:messageboard)
        .permit(:name, :description, :messageboard_group_id, :locked)
    end
  end
end
