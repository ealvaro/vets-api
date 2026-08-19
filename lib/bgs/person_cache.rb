# frozen_string_literal: true

require_relative 'service'

module BGS
  ##
  # When sending data to the VNP tables via BGS it is common to
  # call the `create_person` method to create a record for an
  # individual (e.g. a dependent). When filling out combined forms
  # such as the 686/674, it's possible that the same person may
  # appear multiple times (e.g. as both a new child and a student).
  # We want some way of making sure the same person isn't 'created'
  # multiple times in the VNP tables, so this class acts as a cache
  # to store created person records for later re-use.
  class PersonCache
    ##
    # Internal cache is a hash of the form
    # "#{name}-#{ssn}-#{dob}" => participant
    # Two people are the same if and only if name, ssn, and dob all match
    def initialize(user)
      @user = user
      @cache = {}
    end

    ##
    # person_params must be of the format returned from BGSDependents::Base#create_person_params
    # with the exception that vnp_ptcpnt_id should be nil since we only need to create
    # a participant if this person does not already exist
    # {
    #   ...
    #   vnp_ptcpnt_id: participant_id,
    #   first_nm:
    #   middle_nm:
    #   last_nm:
    #   brthdy_dt:
    #   ssn_nbr:
    #   ...
    # }
    def create_person(person_params)
      first = person_params[:first_nm]&.downcase
      middle = person_params[:middle_nm]&.downcase
      last = person_params[:last_nm]&.downcase
      key = "#{first} #{middle} #{last}-#{person_params[:ssn_nbr]}-#{person_params[:brthdy_dt]}"

      return @cache[key] if @cache[key]

      proc_id = person_params[:vnp_proc_id]
      participant = bgs_service.create_participant(proc_id)
      bgs_service.create_person(person_params.merge({ vnp_ptcpnt_id: participant[:vnp_ptcpnt_id] }))
      @cache[key] = participant

      participant
    end

    protected

    def bgs_service
      @bgs_service ||= BGS::Service.new(@user)
    end
  end
end
