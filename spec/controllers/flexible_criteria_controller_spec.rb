require 'spec_helper'

describe FlexibleCriteriaController do
  FLEXIBLE_CRITERIA_CSV_STRING = "criterion1,1.0,\"description1, for criterion 1\"\ncriterion2,1.0,\"description2, \"\"with quotes\"\"\"\ncriterion3,1.6,description3!\n"

  describe 'An unauthenticated and unauthorized user doing a GET' do
    context '#download' do
      it 'should respond with redirect' do
        get :download, assignment_id: 1
        is_expected.to respond_with :redirect
      end
    end

    context '#upload' do
      it 'should respond with redirect' do
        get :upload, assignment_id: 1
        is_expected.to respond_with :redirect
      end
    end
  end

  describe 'An unauthenticated and unauthorized user doing a POST' do
    context '#download' do
      it 'should respond with redirect' do
        post :download, assignment_id: 1
        is_expected.to respond_with :redirect
      end
    end

    context '#upload' do
      it 'should respond with redirect' do
        post :upload, assignment_id: 1
        is_expected.to respond_with :redirect
      end
    end
  end

  describe 'An authenticated and authorized admin doing a GET' do
    before(:each) do
      @admin = create(:admin)
      @assignment = create(:flexible_assignment)
      @criterion = create(:flexible_criterion,
                          assignment: @assignment,
                          position: 1,
                          name: 'criterion1',
                          description: 'description1, for criterion 1')
      @criterion2 = create(:flexible_criterion,
                           assignment: @assignment,
                           position: 2,
                           name: 'criterion2',
                           description: 'description2, "with quotes"')
      @criterion3 = create(:flexible_criterion,
                           assignment: @assignment,
                           position: 3,
                           name: 'criterion3',
                           description: 'description3!',
                           max_mark: 1.6)
    end

    context '#download' do
      before(:each) do
        get_as @admin, :download, assignment_id: @assignment.id
      end

      it 'should respond with appropriate content' do
        expect(response.header['Content-Type']).to eql('text/csv')
        expect(@response.body).to eql(FLEXIBLE_CRITERIA_CSV_STRING)
        expect(assigns(:assignment)).to be_truthy
      end

      it 'should respond with success' do
        is_expected.to respond_with(:success)
      end
    end

    context '#upload' do
      before(:each) do
        get_as @admin, :upload,
               assignment_id: @assignment.id,
               upload: { flexible: '' }
      end

      it 'should respond with appropriate content' do
        expect(assigns(:assignment)).to be_truthy
      end

      it 'should respond with redirect' do
        is_expected.to respond_with(:redirect)
      end

      it 'should route properly' do
        assert_recognizes({ controller: 'flexible_criteria',
                            assignment_id: '1',
                            action: 'upload' },
                          { path: 'assignments/1/flexible_criteria/upload',
                            method: :post })
      end
    end
  end

  describe 'An authenticated and authorized admin doing a POST' do
    before(:each) do
      @admin = create(:admin, user_name: 'olm_admin')
      @assignment = create(:flexible_assignment)
      @criterion = create(:flexible_criterion,
                          assignment: @assignment,
                          position: 1,
                          name: 'criterion1',
                          description: 'description1, for criterion 1')
      @criterion2 = create(:flexible_criterion,
                           assignment: @assignment,
                           position: 2,
                           name: 'criterion2',
                           description: 'description2, "with quotes"')
      @criterion3 = create(:flexible_criterion,
                           assignment: @assignment,
                           position: 3,
                           name: 'criterion3',
                           description: 'description3!',
                           max_mark: 1.6)
    end

    context '#download' do
      before(:each) do
        post_as @admin, :download, assignment_id: @assignment.id
      end

      it 'should respond with success' do
        is_expected.to respond_with(:success)
      end

      it 'should respond with appropriate content' do
        expect(response.header['Content-Type']).to eql('text/csv')
        expect(@response.body).to eql(FLEXIBLE_CRITERIA_CSV_STRING)
        expect(assigns(:assignment)).to be_truthy
      end
    end

    context '#upload' do
      context 'with file containing incomplete records' do
        before(:each) do
          tempfile = fixture_file_upload('/files/flexible_incomplete.csv')
          post_as @admin,
                  :upload,
                  assignment_id: @assignment.id,
                  upload: { flexible: tempfile }
        end
        it 'should respond with appropriate content' do
          expect(assigns(:assignment)).to be_truthy
        end

        it 'should set the flash' do
          is_expected.to set_flash
        end

        it 'should respond with redirect' do
          is_expected.to respond_with(:redirect)
        end
      end

      context 'with file containing partial records' do
        before(:each) do
          tempfile = fixture_file_upload('/files/flexible_partial.csv')
          post_as @admin,
                  :upload,
                  assignment_id: @assignment.id,
                  upload: { flexible: tempfile }
        end
        it 'should respond with appropriate content' do
          expect(assigns(:assignment)).to be_truthy
        end
        it 'should set the flash' do
          is_expected.to set_flash
        end

        it 'should respond with redirect' do
          is_expected.to respond_with(:redirect)
        end
      end

      context 'with file containing full records' do
        before(:each) do
          FlexibleCriterion.destroy_all
          tempfile = fixture_file_upload('/files/flexible_upload.csv')
          post_as @admin,
                  :upload,
                  assignment_id: @assignment.id,
                  upload: { flexible: tempfile }
          @assignment.reload
          @flexible_criteria = @assignment.get_criteria
        end
        it 'should respond with appropriate content' do
          expect(assigns(:assignment)).to be_truthy
        end
        it 'should set the flash' do
          is_expected.to set_flash
        end

        it 'should respond with redirect' do
          is_expected.to respond_with(:redirect)
        end

        it 'should have successfully uploaded criteria' do
          expect(@assignment.get_criteria.size).to eql(2)
        end
        it 'should keep ordering of uploaded criteria' do
          expect(@flexible_criteria[0].name)
            .to eql('criterion3')
          expect(@flexible_criteria[1].name)
            .to eql('criterion4')

          expect(@flexible_criteria[0].position).to eql(1)
          expect(@flexible_criteria[1].position).to eql(2)
        end
      end

      context 'with a malformed file' do
        before(:each) do
          tempfile = fixture_file_upload('/files/malformed.csv')
          post_as @admin,
                  :upload,
                  assignment_id: @assignment.id,
                  upload: { flexible: tempfile }
        end
        it 'should respond with appropriate content' do
          expect(assigns(:assignment)).to be_truthy
        end

        it 'should set the flash' do
          expect(flash[:error]).to(
            eql([I18n.t('csv.upload.malformed_csv')]))
        end

        it 'should respond with redirect' do
          is_expected.to respond_with(:redirect)
        end
      end

      context 'with a non csv file with csv extension' do
        before(:each) do
          tempfile = fixture_file_upload('/files/pdf_with_csv_extension.csv')
          post_as @admin,
                  :upload,
                  assignment_id: @assignment.id,
                  upload: { flexible: tempfile }
        end
        it 'should respond with appropriate content' do
          expect(assigns(:assignment)).to be_truthy
        end

        it 'should set the flash' do
          expect(flash[:error]).to(
            eql([I18n.t('csv.upload.malformed_csv')]))
        end

        it 'should respond with redirect' do
          is_expected.to respond_with(:redirect)
        end
      end
    end
  end # An authenticated and authorized admin doing a POST
end
