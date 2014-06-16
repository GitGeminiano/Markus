require 'spec_helper'

describe GroupsController do
  describe 'administrator access' do
    let(:admin) { create(:admin) }
    before :each do
      session[:uid] = admin
      session[:timeout] = 2.days.from_now
    end
    # let(:session) { { uid: admin, timeout: 2.days.from_now } }

    describe '#note_message'

    describe 'GET #new' do
      let(:assignment) { create(:assignment) }

      context 'when no group name is specified' do
        before { get :new, assignment_id: assignment }

        it 'assigns specified assignment to variable' do
          expect(assigns(:assignment)).to eq assignment
        end

        it 'creates a new group' do
          expect(Group.all.size).to eq 1
        end
      end

      context 'when a group name is specified' do
        before :each do
          # The user must specify the group name.
          assignment.group_name_autogenerated = false
          assignment.save

          get :new, assignment_id: assignment, new_group_name: 'g2avatar'
        end

        it 'creates a new group with specified name' do
          expect(Group.first.group_name).to eq 'g2avatar'
        end

        it 'errors if group name already exists'
      end
    end

    describe '#remove_group'
    describe '#upload_dialog'
    describe '#download_dialog'
    describe '#rename_group_dialog'
    describe '#rename_group'
    describe '#valid_grouping'
    describe '#invalid_grouping'
    describe '#populate'
    describe '#populate_students'

    describe 'GET #index' do
      let(:assignment) { create(:assignment) }
      before { get :index, assignment_id: assignment }

      it 'populates an array of assignments' do
        expect(assigns(:all_assignments)).to match_array [assignment]
      end

      it 'assigns specified assignment to variable' do
        expect(assigns(:assignment)).to eq assignment
      end

      it 'renders the :index template' do
        expect(response).to render_template :index
      end
    end

    describe '#csv_upload'
    describe '#download_grouplist'
    describe '#use_another_assignment_groups'
    describe '#global_actions'
    describe '#invalidate_groupings'
    describe '#validate_groupings'
    describe '#delete_groupings'
    describe '#add_members'
    describe '#add_member'
    describe '#remove_members'
    describe '#remove_member'
  end
end
