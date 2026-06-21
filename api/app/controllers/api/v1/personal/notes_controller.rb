module Api
  module V1
    module Personal
      class NotesController < BaseController
        before_action :find_active_client

        # POST /api/v1/personal/clients/:client_id/notes
        def create
          note = PersonalNote.new(
            personal: current_user,
            client: @client,
            body: params[:body].to_s.strip,
            visibility: "private"
          )
          if note.save
            render json: serialize(note), status: :created
          else
            render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # GET /api/v1/personal/clients/:client_id/notes
        def index
          notes = PersonalNote.for_client(current_user.id, @client.id).limit(50)
          render json: { notes: notes.map { |n| serialize(n) } }
        end

        private

        def find_active_client
          relationship = current_user.personal_client_relationships
            .where(status: "active", client_id: params[:client_id])
            .first
          if relationship
            @client = relationship.client
          else
            render json: { error: "Client not found or not active" }, status: :not_found
          end
        end

        def serialize(note)
          {
            id:         note.id,
            body:       note.body,
            created_at: note.created_at.iso8601,
          }
        end
      end
    end
  end
end
