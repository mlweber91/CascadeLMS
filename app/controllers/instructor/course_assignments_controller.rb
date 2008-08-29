class Instructor::CourseAssignmentsController < Instructor::InstructorBase
  
  before_filter :ensure_logged_in
  before_filter :set_tab
 
  def index
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments', 'ta_grade_individual', 'ta_view_student_files' )
  
    set_title
  end
  
  def new
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )

    @assignment = Assignment.new
    @journal_field = JournalField.new
    @categories = GradeCategory.for_course( @course )
    
    if @course.course_setting.enable_prog_assignments
      @assignment.programming = true
      @assignment.use_subversion = @course.course_setting.enable_svn
      if @assignment.use_subversion
        @assignment.subversion_server = @course.course_setting.svn_server
      end
    else
      @assignment.programming = false
      @assignment.use_subversion = false
      @assignment.auto_grade = false
    end
    
    set_title
  end
  
  def create
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @points = params[:point_value]
    
    do_exit = false
    # create the assignment
    @assignment = Assignment.new( params[:assignment] )    
    @assignment.course = @course
    @assignment.grade_category_id = params[:grade_category_id].to_i
    do_exit = process_file( params[:file] )
    # see if we need to create a journal settings
    if @assignment.enable_journal
      @journal_field = JournalField.new( params[:journal_field] )
      @assignment.journal_field = @journal_field
    end
    
    ags = AutoGradeSetting.new
    @assignment.auto_grade_setting = ags
    if !@assignment.auto_grade
      # get rid of defaults
      @assignment.auto_grade_setting.disable!      
    end
    
    # do the save
    if !do_exit && @assignment.save
       unless @asgm_document.nil?
         @asgm_document.create_file( params[:file], @app['external_dir'] )
       end
       
       ## style defaults
       if @assignment.auto_grade
         Assignment.transaction do 
           @assignment.ensure_style_defaults 
         end
       end
       
       # create grade item
       if !@points.nil? && @points.to_i > 0
         gi = GradeItem.new
         gi.name = @assignment.title
         gi.date = @assignment.due_date.to_date
         gi.points = @points.to_f
         gi.display_type = "s"
         gi.visible = false
         gi.grade_category_id = @assignment.grade_category_id
         gi.assignment_id = @assignment.id
         gi.course_id = @course.id
         
         gi.save
       end
       
       
       flash[:notice] = 'Assignment was successfully created, you may now upload additional documents and specify auto-grading parameters.'
       
       if @assignment.auto_grade
         redirect_to :action => 'autograde', :id => @assignment
       else
         redirect_to :action => 'index'
       end
    else
       @journal_field = JournalField.new if @journal_field.nil?
       @categories = GradeCategory.for_course( @course )
      
       render :action => 'new'
    end
    # if @document.save
    #  @document.create_file( params[:file], @app['external_dir'] )
    
  end
  
  def move_up
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @assignment = Assignment.find params['id'] rescue @assignment = Assignment.new
    return unless assignment_in_course( @course, @assignment )
    
    (@course.assignments.to_a.find {|s| s.id == @assignment.id}).move_higher
    set_highlight "assignment_#{@assignment.id}"
  	redirect_to :action => 'index'
  end
  
  def move_down
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @assignment = Assignment.find params['id'] rescue @assignment = Assignment.new
    return unless assignment_in_course( @course, @assignment )
    
    (@course.assignments.to_a.find {|s| s.id == @assignment.id}).move_lower
    set_highlight "assignment_#{@assignment.id}"
  	redirect_to :action => 'index'
  end
  
  def destroy
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @assignment = Assignment.find( params['id'] )
    return unless assignment_in_course( @course, @assignment )
    
    @assignment.assignment_documents.each { |x| x.delete_file( @app['external_dir'] ) }
    
    @assignment.destroy
    flash[:notice] = 'Assignment Deleted'
    redirect_to :action => 'index'
  end
  
  def autograde
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    @assignment = Assignment.find( params['id'] )
    return unless assignment_in_course( @course, @assignment )
    return unless assignment_uses_autograde( @course, @assignment )  
    
    if @assignment.auto_grade_setting.nil?
      @assignment.auto_grade_setting = AutoGradeSetting.new
      @assignment.save
    end
    
    @auto_grade_setting = @assignment.auto_grade_setting
  end
  
  def save_autograde
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    @assignment = Assignment.find( params['id'] )
    return unless assignment_in_course( @course, @assignment )
    return unless assignment_uses_autograde( @course, @assignment )  
    
    if @assignment.auto_grade_setting.update_attributes( params[:auto_grade_setting] ) 
      flash[:notice] = "AutoGrade settings changed."
    else
      flash[:badnotice] = "There was an error saving autograde settings."
    end
    
    redirect_to :action => 'autograde', :id => @assignment
  end
  
  def edit
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @assignment = Assignment.find( params['id'] )
    return unless assignment_in_course( @course, @assignment )   
    
    @journal_field = @assignment.journal_field
    @journal_field = JournalField.new if @assignment.journal_field.nil?
    @categories = GradeCategory.for_course( @course ) 
  end
  
  def update
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @assignment = Assignment.find( params['id'] )
    return unless assignment_in_course( @course, @assignment )
    
    begin
      @assignment.grade_category_id = params[:grade_category_id].to_i
      raise 'Assignment update failed.' unless @assignment.update_attributes(params[:assignment]) 
      if @assignment.enable_journal
        if @assignment.journal_field.nil?
          @journal_field = JournalField.new( params[:journal_field] )
          @assignment.journal_field = @journal_field
          @assignment.save
        else
          @assignment.journal_field.update_attributes( params[:journal_field] )
        end
      else
        @assignment.journal_field.destroy unless @assignment.journal_field.nil?
      end
      
      ## see if there is a file to upload
      do_exit = process_file( params[:file], true )
      unless @asgm_document.nil?
         @asgm_document.create_file( params[:file], @app['external_dir'] )
         @assignment.file_uploads = true
         @assignment.save
      end
      
      flash[:notice] = 'Assignment has been updated.'
      redirect_to :action => 'edit', :course => @course, :id => @assignment
    rescue RuntimeError => re
      flash[:badnotice] = re.message
      redirect_to :action => 'edit', :course => @course, :id => @assignment
    end
        
  end
  
  def pmd_settings
      return unless load_course( params[:course] )
      return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
      return unless course_open( @course, :action => 'index' )
      @assignment = Assignment.find( params['id'] )
      return unless assignment_in_course( @course, @assignment )
      return unless assignment_uses_autograde( @course, @assignment )
      return unless assignment_uses_pmd( @course, @assignment )
      
      
      @assignments = Array.new
      # load other assignments in the course
      assignments = Assignment.find(:all, :conditions => ["course_id = ?", @course.id], :order => "open_date asc" )
      assignments.each do |asgn|
        if asgn.auto_grade && ! asgn.auto_grade_setting.nil? && (asgn.auto_grade_setting.student_style || asgn.auto_grade_setting.style)
          @assignments << asgn unless asgn.id == @assignment.id
        end
      end
      
      # this isn't fun - make sure that pmd setting are available
      if @assignment.assignment_pmd_settings.size == 0
        unless @assignment.ensure_style_defaults
          flash[:badnotice] = "There was an error initialize the default Java style checks, please try again later."
          redirect_to :action => 'index', :course => @course
        else 
          flash[:notice] = "Initialized PMD settings to default values."
        end
      end
  end
  
  def copy_pmd
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    @assignment = Assignment.find( params['id'] )
    return unless assignment_in_course( @course, @assignment )
    return unless assignment_uses_autograde( @course, @assignment )
    return unless assignment_uses_pmd( @course, @assignment )
    
    @copy_from = Assignment.find( params['copy_from_id'])   
    return unless assignment_in_course( @course, @copy_from )
    return unless assignment_uses_autograde( @course, @copy_from )
    return unless assignment_uses_pmd( @course, @copy_from )
    
    begin
      pmds = @assignment.pmd_hash
      
      master = @copy_from.pmd_hash
      master.each do |id,pmd|
        pmds[id].enabled = pmd.enabled
        raise "error saving" unless pmds[id].save
      end
      
      flash[:notice] = "PMD settings have been copied."
    rescue Exception => e
      flash[:badnotice] = "There was an error updating the PMD setting for this assignment."
    end
    
    redirect_to :action => 'pmd_settings', :course => @course, :id => @assignment
  end
  
  def save_pmd
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    @assignment = Assignment.find( params['id'] )
    return unless assignment_in_course( @course, @assignment )
    return unless assignment_uses_autograde( @course, @assignment )
    return unless assignment_uses_pmd( @course, @assignment )
    
    begin
      AssignmentPmdSetting.transaction do
        pmds = @assignment.pmd_hash
        pmds.each do |id,pmd|
          #puts "KEY=#{id}"
          #puts pmd.inspect 
          #puts params["apmd_#{id}"]
          
          if params["apmd_#{id}"].nil?
            if pmd.enabled == true
              pmd.enabled = false
              raise "error saving" unless pmd.save
            end
          else
            unless pmd.enabled.to_s.eql?( params["apmd_#{id}"].to_s )
              pmd.enabled = ! pmd.enabled
              raise "error saving" unless pmd.save
            end
          end
        end
      end
      
      flash[:notice] = "PMD settings have been saved."
    rescue
      flash[:badnotice] = "There was an error updating the PMD setting for this assignment."
    end
  
    redirect_to :action => 'pmd_settings', :course => @course, :id => @assignment
  end
  
  def file_move_up
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @assignment = Assignment.find params[:id] rescue @assignment = Assignment.new
    return unless assignment_in_course( @course, @assignment )
    
    @document = AssignmentDocument.find( params[:document] ) rescue @document = AssignmentDocument.new
    return unless document_in_assignment( @document, @assignment )
    
    (@assignment.assignment_documents.to_a.find {|s| s.id == @document.id}).move_higher
    set_highlight "assignment_document_#{@document.id}"
  	redirect_to :action => 'edit', :course => @course, :id => @assignment
  end
  
  def file_move_down
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @assignment = Assignment.find( params[:id] ) rescue @assignment = Assignment.new
    return unless assignment_in_course( @course, @assignment )
    
    @document = AssignmentDocument.find( params[:document] ) rescue @document = AssignmentDocument.new
    return unless document_in_assignment( @document, @assignment )
    
    (@assignment.assignment_documents.to_a.find {|s| s.id == @document.id}).move_lower
    set_highlight "assignment_document_#{@document.id}"
  	redirect_to :action => 'edit', :course => @course, :id => @assignment
  end
  
  def file_delete
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    return unless course_open( @course, :action => 'index' )
    
    @assignment = Assignment.find( params[:id] ) rescue @assignment = Assignment.new
    return unless assignment_in_course( @course, @assignment )
    
    @document = AssignmentDocument.find( params[:document] ) rescue @document = AssignmentDocument.new
    return unless document_in_assignment( @document, @assignment )
    
    if @assignment.assignment_documents.size == 1 && (@assignment.description.nil? || @assignment.description.size == 0)
      flash[:badnotice] = "You can not remove the last file from this assignment unless a textual description is entered first."
    else
      @document.destroy
    end
    redirect_to :action => 'edit', :course => @course, :id => @assignment    
  end
  
  def download
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_course_assignments' )
    
    @assignment = Assignment.find( params[:id] ) rescue @assignment = Assignment.new
    return unless assignment_in_course( @course, @assignment )
    
    @document = AssignmentDocument.find( params[:document] ) rescue @document = AssignmentDocument.new
    return unless document_in_assignment( @document, @assignment )
    
    begin  
      send_file @document.resolve_file_name(@app['external_dir']), :filename => @document.filename, :type => "#{@document.content_type}", :disposition => 'download'  
    rescue
      flash[:badnotice] = "Sorry - the requested document has been deleted or is corrupt.  Please notify your administrator of the problem and mention 'document id #{@document.id}'."
      redirect_to :action => 'index'
    end
  end
  
  
  
  
  
private  
  #### PRIVATE METHODS BELOW
  def set_tab
    @show_course_tabs = true
    @tab = "course_instructor"
  end
  
  def set_title
    @title = "Course Assignments - #{@course.title}"
  end

  
end
