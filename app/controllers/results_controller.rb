require 'zip'
class ResultsController < ApplicationController
  include TagsHelper
  before_filter :authorize_only_for_admin,
                except: [:codeviewer, :edit, :update_mark, :view_marks,
                         :create, :add_extra_mark, :next_grouping,
                         :update_overall_comment, :remove_extra_mark,
                         :toggle_marking_state,
                         :download, :download_zip,
                         :note_message,
                         :update_remark_request, :cancel_remark_request]
  before_filter :authorize_for_ta_and_admin,
                only: [:edit, :update_mark, :create, :add_extra_mark,
                       :next_grouping, :update_overall_comment,
                       :remove_extra_mark,
                       :toggle_marking_state,
                       :note_message]
  before_filter :authorize_for_user,
                only: [:codeviewer, :download, :download_zip, :run_tests]
  before_filter :authorize_for_student,
                only: [:view_marks, :update_remark_request,
                       :cancel_remark_request]
  after_filter  :update_remark_request_count,
                only: [:update_remark_request, :cancel_remark_request,
                       :set_released_to_students]

  def note_message
    @result = Result.find(params[:id])
    if params[:success]
      flash[:note_success] = I18n.t('notes.success')
    else
      flash[:fail_notice] = I18n.t('notes.error')
    end
  end

  def edit
    @result = Result.find(params[:id])
    @assignment = @result.submission.assignment
    @submission = @result.submission

    if @submission.remark_submitted?
      @old_result = @submission.get_original_result
    else
      @old_result = nil
    end

    @grouping = @result.submission.grouping
    @not_associated_tags = get_tags_not_associated_with_grouping(@grouping.id)
    @group = @grouping.group
    @files = @submission.submission_files.sort do |a, b|
      File.join(a.path, a.filename) <=> File.join(b.path, b.filename)
    end
    @feedback_files = @submission.feedback_files
    @first_file = @files.first
    @extra_marks_points = @result.extra_marks.points
    @extra_marks_percentage = @result.extra_marks.percentage
    @marks_map = Hash.new
    @old_marks_map = Hash.new
    @mark_criteria = @assignment.get_criteria
    @assignment.get_criteria.each do |criterion|
      mark = criterion.marks.find_or_create_by(result_id: @result.id)
      @marks_map[criterion.id] = mark
      # Loading up previous results for the case of a remark
      if @old_result
        oldmark = criterion.marks.find_or_create_by(result_id: @old_result.id)
        oldmark.save(validate: false)
        @old_marks_map[criterion.id] = oldmark
      end

      Mark.skip_callback(:save, :after, :update_result_mark)
      mark.save(validate: false)
      Mark.set_callback(:save, :after, :update_result_mark)
    end

    @result.update_total_mark
    groupings = Grouping.get_groupings_for_assignment(@assignment,
                                                      current_user)
    # We sort by group name by default
    groupings = groupings.sort do |a, b|
      a.group.group_name <=> b.group.group_name
    end

    current_grouping_index = groupings.index(@grouping)
    if current_grouping_index.nil?
      @next_grouping = groupings.first
      @previous_grouping = groupings.last
    else
      unless groupings[current_grouping_index + 1].nil?
        @next_grouping = groupings[current_grouping_index + 1]
      end
      if (current_grouping_index - 1) >= 0
        @previous_grouping = groupings[current_grouping_index - 1]
      end
    end

    m_logger = MarkusLogger.instance
    m_logger.log("User '#{current_user.user_name}' viewed submission (id: #{@submission.id})" +
                 "of assignment '#{@assignment.short_identifier}' for group '" +
                 "#{@group.group_name}'")

    @host = Rails.application.config.action_controller.relative_url_root

    # Sets up the tags for the tag pane.
    # Creates a variable for all the tags not used
    # and all the tags that are used by the assignment.
    @all_tags = Tag.all
    @grouping_tags = get_tags_for_grouping(@grouping.id)
    @not_grouping_tags = get_tags_not_associated_with_grouping(@grouping.id)

    # Gets the top tags and their usage.
    @top_tags = get_top_tags
    @top_tags_num = Hash.new
    @top_tags.each do |current|
      @top_tags_num[current.id] = get_num_groupings_for_tag(current.id)
    end

    # Respond to AJAX request.
    respond_to do |format|
      format.html
      format.json do
        @request_type = params[:type]

        # Checks the operation requested.
        if @request_type.eql? 'add'
          create_grouping_tag_association_from_existing_tag(
              params[:grouping_id],
              params[:tag_id])
        else
          delete_grouping_tag_association(params[:tag_id],
                                          Grouping.find(params[:grouping_id]))
        end

        # Renders nothing.
        render nothing: true
      end
    end
  end

  def run_tests
    grouping_id = params[:grouping_id]
    # TODO: The submission id is set incorrectly as the grouping_id
    submission_id = Result.find(params[:id]).submission.id

    begin
      AutomatedTestsHelper.request_a_test_run(grouping_id,
                                              'submission',
                                              @current_user,
                                              submission_id)
    rescue => e
      # TODO: really shouldn't be leaking error if student.
      if current_user.admin?
        flash_message(:error, e.message)
      else
        # TODO: Better error handling for students
        flash_message(:error, 'Error running tests')
      end
    end
    redirect_to :back
  end

  ##  Tag Methods  ##

  def add_tag
    create_grouping_tag_association_from_existing_tag(params[:grouping_id],
                                                      params[:tag_id])
    respond_to do |format|
      format.html do
        redirect_to :back
      end
    end
  end

  def remove_tag
    delete_grouping_tag_association(params[:tag_id],
                                    Grouping.find(params[:grouping_id]))
    respond_to do |format|
      format.html do
        redirect_to :back
      end
    end
  end

  def next_grouping
    grouping = Grouping.find(params[:id])
    if grouping.has_submission? && grouping.is_collected?
        redirect_to action: 'edit',
                    id: grouping.current_submission_used.get_latest_result.id
    else
      redirect_to controller: 'submissions',
                  action: 'browse'
    end
  end

  def set_released_to_students
    @result = Result.find(params[:id])
    released_to_students = !@result.released_to_students
    if params[:old_id]
      @old_result = Result.find(params[:old_id])
      @old_result.released_to_students = released_to_students
      @old_result.save
    end
    @result.released_to_students = released_to_students
    @result.save
    m_logger = MarkusLogger.instance
    assignment = @result.submission.assignment
    if params[:value] == 'true'
      m_logger.log("Marks released for assignment '#{assignment.short_identifier}', ID: '" +
                   "#{assignment.id}' (for 1 group).")
    else
      m_logger.log("Marks unreleased for assignment '#{assignment.short_identifier}', ID: '" +
                   "#{assignment.id}' (for 1 group).")
    end
  end

  # Toggles the marking state
  def toggle_marking_state
    @result = Result.find(params[:id])
    @old_marking_state = @result.marking_state

    if @result.marking_state == Result::MARKING_STATES[:complete]
      @result.marking_state = Result::MARKING_STATES[:incomplete]
    else
      @result.marking_state = Result::MARKING_STATES[:complete]
    end

    if @result.save
      @result.submission.assignment.assignment_stat.refresh_grade_distribution
      @result.submission.assignment.update_results_stats
      render 'results/toggle_marking_state'
    else # Failed to pass validations
      # Show error message
      render 'results/marker/show_result_error'
    end
  end

  def download
    if params[:download_zip_button]
      download_zip
      return
    end
    #Ensure student doesn't download a file not submitted by his own grouping
    unless authorized_to_download?(file_id: params[:select_file_id])
      render 'shared/http_status', formats: [:html],
             locals: { code: '404',
                          message: HttpStatusHelper::ERROR_CODE[
                              'message']['404'] }, status: 404,
             layout: false
      return
    end
    file = SubmissionFile.find(params[:select_file_id])
    begin
      if params[:include_annotations] == 'true' && !file.is_supported_image?
        file_contents = file.retrieve_file(true)
      else
        file_contents = file.retrieve_file
      end
    rescue Exception => e
      flash[:file_download_error] = e.message
      redirect_to action: 'edit',
                  assignment_id: params[:assignment_id],
                  submission_id: file.submission,
                  id: file.submission.get_latest_result.id
      return
    end
    filename = file.filename
    #Display the file in the page if it is an image/pdf, and download button
    #was not explicitly pressed
    if file.is_supported_image? && !params[:show_in_browser].nil?
      send_data file_contents, type: 'image', disposition: 'inline',
        filename: filename
    else
      send_data file_contents, filename: filename
    end
  end

  def download_zip

    #Ensure student doesn't download files not submitted by his own grouping
    unless authorized_to_download?(submission_id: params[:submission_id])
      render 'shared/http_status', formats: [:html],
             locals: { code: '404',
                          message: HttpStatusHelper::ERROR_CODE[
                              'message']['404'] }, status: 404,
             layout: false
      return
    end
    assignment = Assignment.find(params[:assignment_id])
    submission = Submission.find(params[:submission_id])
    grouping = Grouping.find(submission.grouping_id)

    revision_number = submission.revision_number
    repo_folder = assignment.repository_folder
    zip_name = "#{repo_folder}-#{grouping.group.repo_name}"

    if submission.blank?
      render text: t('student.submission.no_files_available')
      return
    end

    zip_path = if params[:include_annotations] == 'true'
                 "tmp/#{assignment.short_identifier}_" +
                     "#{grouping.group.group_name}_r#{revision_number}_ann.zip"
               else
                 "tmp/#{assignment.short_identifier}_" +
                     "#{grouping.group.group_name}_r#{revision_number}.zip"
               end

    files = submission.submission_files
    Zip::File.open(zip_path, Zip::File::CREATE) do |zip_file|
      files.each do |file|
        begin
          if params[:include_annotations] == 'true' && !file.is_supported_image?
            file_content = file.retrieve_file(true)
          else
            file_content = file.retrieve_file
          end
        rescue Exception => e
          render text: t('student.submission.missing_file',
                            file_name: file.filename, message: e.message)
          return
        end
        # Create the folder in the Zip file if it doesn't exist
        zip_file.mkdir(zip_name) unless zip_file.find_entry(zip_name)

        zip_file.get_output_stream(File.join(zip_name, file.filename)) do |f|
          f.puts file_content
        end
      end
    end
    # Send the Zip file
    send_file zip_path, disposition: 'inline',
              filename: zip_name + '.zip'
  end

  def codeviewer
    @assignment = Assignment.find(params[:assignment_id])
    @submission_file_id = params[:submission_file_id]
    @focus_line = params[:focus_line]

    @file = SubmissionFile.find(@submission_file_id)
    @result = @file.submission.get_latest_result
    # Is the current user a student?
    if current_user.student?
      # The Student does not have access to this file. Display an error.
      if @file.submission.grouping.membership_status(current_user).nil?
        flash_message(:error, t('submission_file.error.no_access',
                                submission_file_id: @submission_file_id))
        redirect_to :back
        return
      end
    end

    @annots = @file.annotations
    @all_annots = @file.submission.annotations

    begin
      @file_contents = @file.retrieve_file
    rescue Exception => e
      flash_message(:error, e.message)
      render partial: 'shared/handle_error', locals: { error: e.message }
      return
    end
    @code_type = @file.get_file_type

    render template: 'results/common/codeviewer'
  end

  def update_mark
    result_mark = Mark.find(params[:mark_id])
    result_mark.mark = params[:mark]
    submission = result_mark.result.submission  # get submission for logging
    group = submission.grouping.group           # get group for logging
    assignment = submission.grouping.assignment # get assignment for logging
    m_logger = MarkusLogger.instance

    if result_mark.save
      m_logger.log("User '#{current_user.user_name}' updated mark for " +
                   "submission (id: #{submission.id}) of " +
                   "assignment #{assignment.short_identifier} for " +
                   "group #{group.group_name}.",
                   MarkusLogger::INFO)
      render text: "#{result_mark.get_mark}," +
                   "#{result_mark.result.get_subtotal}," +
                   "#{result_mark.result.total_mark}"
    else
      m_logger.log("Error while trying to update mark of submission. " +
                   "User: #{current_user.user_name}, " +
                   "Submission id: #{submission.id}, " +
                   "Assignment: #{assignment.short_identifier}, " +
                   "Group: #{group.group_name}.",
                   MarkusLogger::ERROR)
      render text: result_mark.errors.full_messages.join, status: :bad_request
    end
  end

  def view_marks
    @assignment = Assignment.find(params[:assignment_id])
    @grouping = current_user.accepted_grouping_for(@assignment.id)

    if @grouping.nil?
      redirect_to controller: 'assignments',
                  action: 'student_interface',
                  id: params[:id]
      return
    end
    unless @grouping.has_submission?
      render 'results/student/no_submission'
      return
    end
    @submission = @grouping.current_submission_used
    unless @submission.has_result?
      render 'results/student/no_result'
      return
    end

    @result = @submission.get_original_result
    @old_result = nil
    if @submission.remark_submitted?
      @old_result = @result
      @result = @submission.remark_result
      # Check if remark request has been submitted but not released yet
      if !@result.remark_request_submitted_at.nil? && !@result.released_to_students
        render 'results/student/no_remark_result'
        return
      end
    end

    unless @result.released_to_students
      render 'results/student/no_result'
      return
    end

    @annotation_categories = @assignment.annotation_categories
    @group = @grouping.group
    @files = @submission.submission_files.sort do |a, b|
      File.join(a.path, a.filename) <=> File.join(b.path, b.filename)
    end
    @feedback_files = @submission.feedback_files
    @first_file = @files.first
    @extra_marks_points = @result.extra_marks.points
    @extra_marks_percentage = @result.extra_marks.percentage
    @marks_map = Hash.new
    @old_marks_map = Hash.new
    @mark_criteria = @assignment.get_criteria
    @assignment.get_criteria.each do |criterion|
      mark = criterion.marks.find_or_create_by(result_id: @result.id)
      mark.save(validate: false)
      @marks_map[criterion.id] = mark

      if @old_result
        oldmark = criterion.marks.find_or_create_by(result_id: @old_result.id)
        oldmark.save(validate: false)
        @old_marks_map[criterion.id] = oldmark
      end
    end

    @host = Rails.application.config.action_controller.relative_url_root

    m_logger = MarkusLogger.instance
    m_logger.log("Student '#{current_user.user_name}' viewed results for assignment " +
                 "'#{@assignment.short_identifier}'.")
  end

  def add_extra_mark
    @result = Result.find(params[:id])
    if request.post?
      @extra_mark = ExtraMark.new
      @extra_mark.result = @result
      @extra_mark.unit = ExtraMark::POINTS
      if @extra_mark.update_attributes(extra_mark_params)
        # need to re-calculate total mark
        @result.update_total_mark
        render template: 'results/marker/insert_extra_mark'
      else
        render template: 'results/marker/add_extra_mark_error'
      end
      return
    end
    render template: 'results/marker/add_extra_mark'
  end

  #Deletes an extra mark from the database and removes it from the html
  def remove_extra_mark
    #find the extra mark and destroy it
    @extra_mark = ExtraMark.find(params[:id])
    @extra_mark.destroy
    #need to recalculate total mark
    @result = @extra_mark.result
    @result.update_total_mark
    render template: 'results/marker/remove_extra_mark'
  end

  def update_overall_comment
    Result.find(params[:id]).update_attributes(
      overall_comment: params[:result][:overall_comment])
    head :ok
  end

  def update_remark_request
    @assignment = Assignment.find(params[:assignment_id])
    if @assignment.past_remark_due_date?
      head :bad_request
    else
      @submission = Submission.find(params[:id])
      @submission.update_attributes(
        remark_request: params[:submission][:remark_request],
        remark_request_timestamp: Time.zone.now
      )
      if params[:save]
        render 'update_remark_request', formats: [:js]
      elsif params[:submit]
        unless @submission.remark_result
          @submission.make_remark_result
        end
        @submission.remark_result.update_attributes(
          marking_state: Result::MARKING_STATES[:incomplete])
        @submission.get_original_result.update_attributes(
          released_to_students: false)
        render js: 'location.reload();'
      else
        head :bad_request
      end
    end
  end

  # Allows student to cancel a remark request.
  def cancel_remark_request
    submission = Submission.find(params[:submission_id])

    submission.remark_result.destroy
    submission.get_original_result.update_attributes(
      released_to_students: true)

    redirect_to controller: 'results',
                action: 'view_marks',
                id: params[:id]
  end

  def delete_grace_period_deduction
    @grouping = Grouping.find(params[:id])
    grace_deduction = GracePeriodDeduction.find(params[:deduction_id])
    grace_deduction.destroy
  end

  private

  #Return true if submission_id or file_id matches between accepted_student and
  #current_user. This is to prevent students from downloading files that they
  #or their group have not submitted. Return false otherwise.
  def authorized_to_download?(map)
    #If the user is a ta or admin, return true as they are authorized.
    if current_user.admin? || current_user.ta?
      return true
    end
    submission = if map[:file_id]
                   sub_file = SubmissionFile.find_by_id(map[:file_id])
                   sub_file.submission unless sub_file.nil?
                 elsif map[:submission_id]
                   Submission.find(map[:submission_id])
                 end
    if submission
      #Check that current_user is in fact in grouping that sub_file belongs to
      !submission.grouping.accepted_students.find { |user|
        user == current_user
      }.nil?
    else
      false
    end
  end

  def update_remark_request_count
    Assignment.find(params[:assignment_id]).update_remark_request_count
  end

  private

  def extra_mark_params
    params.require(:extra_mark).permit(:result,
                                       :description,
                                       :extra_mark)
  end
end
