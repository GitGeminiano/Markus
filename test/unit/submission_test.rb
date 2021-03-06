require File.expand_path(File.join(File.dirname(__FILE__), '..', 'test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'blueprints', 'helper'))

require 'shoulda'

class SubmissionTest < ActiveSupport::TestCase

  should have_many :submission_files
  should have_many :test_script_results

  should 'automatically create a result' do
    s = Submission.make
    s.save
    assert_not_nil s.get_latest_result, 'Result was supposed to be created automatically'
    assert_equal s.get_latest_result.marking_state, Result::MARKING_STATES[:incomplete], 'Result marking_state should have been automatically set to incomplete'
  end

  should 'create a new remark result' do
    s = Submission.make
    s.update(remark_request_timestamp: Time.zone.now)
    s.make_remark_result
    assert_not_nil s.remark_result, 'Remark result was supposed to be created'
    assert_equal s.remark_result.marking_state,
                 Result::MARKING_STATES[:incomplete],
                 'Remark result marking_state should have been ' +
                   'automatically set to incomplete'
  end

  context 'A submission with a remark result submitted' do
    setup do
      @submission = Submission.make
      @submission.update(remark_request_timestamp: Time.zone.now)
      @submission.make_remark_result
    end

    should 'return true on has_remark? call' do
      assert @submission.has_remark?
    end

    should 'return true on remark_submitted? call' do
      assert @submission.remark_submitted?
    end
  end

  context 'A submission with a remark result created but not submitted' do
    setup do
      @submission = Submission.make
      @result = Result.make(submission: @submission)
      @submission.update(remark_request_timestamp: Time.zone.now)
      @submission.make_remark_result
      @submission.remark_result.update(remark_request_submitted_at: nil)
    end

    should 'return true on has_remark? call' do
      assert @submission.has_remark?
    end

    should 'return false on remark_submitted? call' do
      assert !@submission.remark_submitted?
    end
  end

  context 'A submission with no remark results' do
    setup do
      @submission = Submission.make
      @submission.save
    end
    should 'return false on has_remark? call' do
      assert !@submission.has_remark?
    end
    should 'return false on remark_submitted? call' do
      assert !@submission.remark_submitted?
    end
  end

  context 'The Submission class' do
    should 'be able to find a submission object by group name and assignment short identifier' do
      # existing submission
      assignment = Assignment.make
      group = Group.make
      grouping = Grouping.make(:assignment => assignment,
                               :group => group)
      submission = Submission.make(:grouping => grouping)

      sub2 = Submission.get_submission_by_group_and_assignment(group.group_name,
                                                                assignment.short_identifier)
      assert_not_nil(sub2)
      assert_instance_of(Submission, sub2)
      assert_equal(submission, sub2)
      # non existing test results
      assert_nil(
          Submission.get_submission_by_group_and_assignment(
                'group_name_not_there',
                'A_not_there'))
    end
  end

  should 'create a remark result' do
    s = Submission.make
    s.update(remark_request_timestamp: Time.zone.now)
    s.make_remark_result
    assert_not_nil s.remark_result, 'Remark result was supposed to be created'
    assert_equal s.remark_result.marking_state,
                 Result::MARKING_STATES[:incomplete],
                 'Remark result marking_state should have been ' +
                   'automatically set to incomplete'
  end

end
