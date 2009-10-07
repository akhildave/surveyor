# The Surveyor controller a user taking a survey. It is semi-RESTful since it does not have a concrete representation model.
# The "resource" is a survey attempt/session populating a response set.

class SurveyorController < ApplicationController
  
  # Layout
  layout Surveyor::Config['default.layout'] || 'surveyor_default'
  
  # Extending surveyor
  include SurveyorControllerExtensions if Surveyor::Config['extend_controller'] && defined? SurveyorControllerExtensions
  before_filter :extend_actions
  
  # RESTful authentication
  if Surveyor::Config['use_restful_authentication']
    include AuthenticatedSystem
    before_filter :login_required
  end
  
  # Get the response set or current_user
  before_filter :get_response_set, :except => [:new, :create]
  before_filter :get_current_user, :only => [:new, :create]
  
  # Actions
  def new
    @surveys = Survey.find(:all)
  end
  def create
    if (@survey = Survey.find_by_access_code(params[:survey_code])) && (@response_set = ResponseSet.create(:survey => @survey, :user_id => @current_user))
      flash[:notice] = "Survey was successfully started."
      redirect_to(edit_my_survey_path(:survey_code => @survey.access_code, :response_set_code  => @response_set.access_code))
    else
      flash[:notice] = "Unable to find that survey"
      redirect_to(available_surveys_path)
    end
  end
  def show
  end
  def edit
    @dependents = (@response_set.unanswered_dependencies - @section.questions) || []
  end
  def update
    if params[:responses] or params[:response_groups]
      saved = @response_set.update_attributes(:response_attributes => (params[:responses] || {}).dup , :response_group_attributes => (params[:response_groups] || {}).dup) #copy (dup) to preserve params because we manipulate params in the response_set methods
      if (saved && params[:finish])
        @response_set.complete!
        saved = @response_set.save!
      end
    end
    respond_to do |format|
      format.html do
        if saved && params[:finish]
          flash[:notice] = "Completed survey"
          redirect_to surveyor_default_finish
        else
          flash[:notice] = "Unable to update survey" if !saved and !saved.nil? # saved.nil? is true if there are no questions on the page (i.e. if it only contains a label)
          redirect_to :action => "edit", :anchor => anchor_from(params[:section]), :params => {:section => @section.id}
        end
      end
      # No redirect needed if we're talking to the page via json
      format.js do
        dependent_hash = @response_set.all_dependencies
        render :json => {:show => dependent_hash[:show].map{|q| "question_#{q.id}"}, :hide => dependent_hash[:hide].map{|q| "question_#{q.id}"} }.to_json
      end
    end
  end

  private
  
  # Filters
  def get_current_user
    @current_user = self.respond_to?(:current_user) ? self.current_user : nil
  end
  def get_response_set
    if @response_set = ResponseSet.find_by_access_code(params[:response_set_code])
      @survey = @response_set.survey
      @section = @survey.sections.find_by_id(section_id_from(params[:section])) || @survey.sections.first
    else
      flash[:notice] = "Unable to find your responses to the survey"
      redirect_to(available_surveys_path)
    end
  end
  
  # Params: the name of some submit buttons store the section we'd like to go to. for repeater questions, an anchor to the repeater group is also stored
  # e.g. params[:section] = {"1"=>{"question_group_1"=>"<= add row"}}
  def section_id_from(p)
    p.respond_to?(:keys) ? p.keys.first : p
  end
  def anchor_from(p)
    p.respond_to?(:keys) && p[p.keys.first].respond_to?(:keys) ? p[p.keys.first].keys.first : nil
  end
  
  # Extending surveyor
  def surveyor_default_finish
    # http://www.postal-code.com/mrhappy/blog/2007/02/01/ruby-comparing-an-objects-class-in-a-case-statement/
    # http://www.skorks.com/2009/08/how-a-ruby-case-statement-works-and-what-you-can-do-with-it/
    case finish = Surveyor::Config['default.finish']
    when String
      return finish
    when Symbol
      return self.send(finish)
    else
      return '/surveys'
    end
  end
  def extend_actions
    # http://blog.mattwynne.net/2009/07/11/rails-tip-use-polymorphism-to-extend-your-controllers-at-runtime/
    self.extend SurveyorControllerExtensions::Actions if Surveyor::Config['extend_controller'] && defined? SurveyorControllerExtensions::Actions
  end

end
