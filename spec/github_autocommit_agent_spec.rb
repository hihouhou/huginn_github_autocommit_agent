require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::GithubAutocommitAgent do
  before(:each) do
    @valid_options = Agents::GithubAutocommitAgent.new.default_options
    @checker = Agents::GithubAutocommitAgent.new(:name => "GithubAutocommitAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
