require 'FreshItems'

class FeedController < ApplicationController
  
  layout 'noright', :except => :index
  
  before_filter :ensure_logged_in, :except => :index
  before_filter :set_tab, :except => :index
  
  def subscribe
    return unless load_course( params[:course] )
    return unless allowed_to_see_course( @course, @user )
    
    return unless course_allows_rss( @course )
  end
  
  def index
    return unless load_course( params[:course] )
    
    @user = rss_authorize( "CSCourseware RSS feed for course '#{@course.title}'.")
    
    return if @user.nil?
    
    unless @user.nil?
      params[:format] = 'xml'
      @course = load_course( params[:course] ) 
      if @course
        if course_allows_rss( @course )
          if allowed_to_see_course( @course, @user )     
            respond_to do |format| 
              format.xml {
                 @recent_activity = FreshItems.fresh( @course, @app['recent_items'].to_i )
                 #headers["Content-Type"] = "application/rss+xml"
            
                 @fresh_date = nil
                 if ( @recent_activity.size > 0 )
                   if ( @recent_activity[0].class.to_s.eql?('Assignment' ) ) 
                     @fresh_date = @recent_activity[0].open_date
                   else
                     @fresh_date = @recent_activity[0].created_at
                   end
                 end
               }
             end
          end
          #render_text( 'You are not authorized to view this RSS feed.', 401 ) 
        end
        #render_text( 'You are not authorized to view this RSS feed.', 401 ) 
      end
      #render_text( 'You are not authorized to view this RSS feed.', 401 ) 
    end
    
  end
  
  
  private
  def course_allows_rss( course )
    unless course.course_setting.enable_rss
      flash[:badnotice] = "This course does not currently have RSS feeds enabled.  Please contact your instructor if you think this is in error."
      redirect_to :controller => '/overview', :course => course
    end
    true
  end
  

  def set_tab
    @show_course_tabs = true
    @tab = "course_overview"
    @title = "Subscribe to a Course's RSS feed"
  end
  
end
