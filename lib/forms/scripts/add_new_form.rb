# frozen_string_literal: true

# This script automates the addition of new forms to vets-api and vets-website.
# It is intended to be run locally by developers, not on deployed servers.
#
# Each method targets a specific file or set of files and can be run individually
# or all at once via `add_all`. Forms are passed as a comma-separated FORM= param;
# append -UPLOAD to a form ID to add it as an uploadable form rather than a standard form.
#
# Params:
#   METHOD=  — the method to invoke (required)
#   FORM=    — comma-separated list of form IDs to add (required for most methods)
#   SERVICE= — the intake service; currently only LBI is supported (required for add_all)
#   VETS_WEBSITE= — path to vets-website repo (optional; defaults to ../vets-website)

class AddNewForm
  # bundle exec rails runner lib/forms/scripts/add_new_form.rb METHOD=add_all SERVICE=LBI FORM=20-10206,21-0845-UPLOAD
  def add_all
    validate_service!
    add_to_vets_api
    add_vets_api_integration_test
    add_to_vets_website_constants
    add_vets_website_mocks
    add_vets_website_e2e_tests
  end

  # bundle exec rails runner lib/forms/scripts/add_new_form.rb METHOD=add_to_vets_api FORM=20-10206,21-0845-UPLOAD
  def add_to_vets_api
    new_form_inputs = form_ids.each_with_object({ basic_forms: [], uploads: [] }) do |input, acc|
      input.end_with?('-UPLOAD') ? acc[:uploads] << input : acc[:basic_forms] << input
    end

    model_path = Rails.root.join('app', 'models', 'form_profile.rb')
    content = File.read(model_path)
    if new_form_inputs[:basic_forms].any?
      existing = content.match(/RESTRICTED_FORMS = %w\[\n(.*?)\n\s+\]\.freeze/m)[1].split
      new_forms = (existing + new_form_inputs[:basic_forms]).uniq
      regex = /RESTRICTED_FORMS = %w\[\n.*?\n\s+\]\.freeze/m
      replacement = "RESTRICTED_FORMS = %w[\n#{new_forms.join("\n")}\n].freeze"
      replace_in_file(model_path, content, regex, replacement)
    end
    if new_form_inputs[:uploads].any?
      existing = content.match(/form_upload: %w\[\n(.*?)\n\s+\]/m)[1].split
      new_forms = (existing + new_form_inputs[:uploads]).uniq
      regex = /form_upload: %w\[\n.*?\n\s+\]/m
      replacement = "form_upload: %w[\n#{new_forms.join("\n")}\n]"
      replace_in_file(model_path, content, regex, replacement)
    end
    RuboCop::CLI.new.run(['--autocorrect', model_path.to_s])
  end

  INTEGRATION_TEST_TEMPLATE = <<~TEXT

    describe 'form %<form_id>s' do
      let!(:form) { create(:form_submission, user_account_id: account_id, form_type: '%<form_id>s') }

      it 'is returned in lighthouse submission statuses' do
        get '/v0/my_va/submission_statuses'

        expect(response).to have_http_status(:ok)
        results = JSON.parse(response.body)['data']
        expect(results.size).to be == 1
        expect(results.first['attributes']['form_type']).to eq('%<form_id>s')
      end
    end
  TEXT
  INTEGRATION_TEST_TAG = '# ADD NEW FORM INTEGRATION TESTS HERE. DO NOT REMOVE THIS COMMENT'

  # bundle exec rails runner lib/forms/scripts/add_new_form.rb METHOD=add_vets_api_integration_test
  # FORM=20-10206,21-0845-UPLOAD
  def add_vets_api_integration_test
    spec_location = Rails.root.join('spec', 'requests', 'v0', 'my_va', 'submission_statuses_spec.rb')
    content = File.read(spec_location)

    new_forms = form_ids.map do |form_id|
      format(INTEGRATION_TEST_TEMPLATE, form_id:)
    end
    regex = /#{INTEGRATION_TEST_TAG}/m
    replacement = "#{new_forms.join}#{INTEGRATION_TEST_TAG}"
    replace_in_file(spec_location, content, regex, replacement)
    RuboCop::CLI.new.run(['--autocorrect', spec_location.to_s])
  end

  # bundle exec rails runner lib/forms/scripts/add_new_form.rb METHOD=add_to_vets_website_constants
  # FORM=20-10206,21-0845-UPLOAD
  def add_to_vets_website_constants
    constants_location = File.join(vets_website_location, 'src', 'platform', 'forms', 'constants.js')
    constant_start = 'export const VA_FORM_IDS = Object.freeze({'
    constant_end = '});'

    additional_entries = form_ids.map do |form_name|
      snake = "FORM_#{form_name.gsub('-', '_').upcase}"
      "#{snake}: '#{form_name}',"
    end
    content = File.read(constants_location)
    match = content.match(/#{Regexp.escape(constant_start)}(.*?)#{Regexp.escape(constant_end)}/m)
    existing_entries = match ? match[1].split("\n").map(&:strip).reject(&:empty?) : []
    all_entries = (existing_entries + additional_entries).uniq.map { |e| "  #{e}" }.join("\n")
    regex = /#{Regexp.escape(constant_start)}.*?#{Regexp.escape(constant_end)}/m
    replacement = "#{constant_start}\n#{all_entries}\n#{constant_end}"
    replace_in_file(constants_location, content, regex, replacement)
    system('yarn', 'eslint', '--fix', constants_location.to_s, chdir: vets_website_location)
  end

  MOCK_TEMPLATE = <<~TEXT
    {
      id: '417f5024-1154-4949-9e2e-4a196726014f',
      type: 'submission_status',
      attributes: {
        id: '%<uuid>s',
        detail: '',
        formType: '%<form>s',
        message: null,
        status: 'vbms',
        createdAt: '%<time>s',
        updatedAt: fns.formatISO(daysAgo),
        pdfSupport: false,
      },
    },
  TEXT

  # bundle exec rails runner lib/forms/scripts/add_new_form.rb METHOD=add_vets_website_mocks
  # FORM=20-10206,21-0845-UPLOAD
  def add_vets_website_mocks
    mock_location = File.join(vets_website_location, 'src', 'applications', 'personalization', 'dashboard', 'mocks',
                              'benefit-applications', 'index.js')
    content = File.read(mock_location)
    tag = '// COMMENT USED FOR NEW MOCK AUTOMATION. DO NOT REMOVE.'

    new_forms = form_ids.map do |form|
      uuid = SecureRandom.uuid
      time = Time.zone.now
      format(MOCK_TEMPLATE, uuid:, form:, time:)
    end
    regex = /#{tag}/m
    replacement = "#{new_forms.join}#{tag}"
    replace_in_file(mock_location, content, regex, replacement)
    system('yarn', 'eslint', '--fix', mock_location.to_s, chdir: vets_website_location)
  end

  E2E_TEMPLATE = <<~TEXT

    describe('%<form>s', () => {
      const mocks = createApplications();
      const formMock = mocks.data.find(mock => mock.attributes.formType === '%<form>s');
      function mockData(status) {
        formMock.attributes.status = status;
        return {
          data: [formMock],
          errors: [],
        };
      }

      beforeEach(() => {
        mockUser.data.attributes.inProgressForms = [];
        cy.login(mockUser);
      });

      it('should show a submission card with "Submission in Progress" when status is pending', () => {
        cy.intercept('GET', '/v0/my_va/submission_statuses', req => {
          req.reply({
            statusCode: 200,
            body: mockData('pending'),
          });
        });
        cy.visit(manifest.rootUrl);

        cy.findAllByTestId('submitted-application').should('have.length', 1);
        cy.findAllByTestId('submitted-application')
          .first()
          .should('contain.text', '%<lower_case_form>s');
        cy.injectAxe();
        cy.axeCheck();
      });

      it('should show a 12345 submission card when status is received', () => {
        cy.intercept('GET', '/v0/my_va/submission_statuses', req => {
          req.reply({
            statusCode: 200,
            body: mockData('received'),
          });
        });
        cy.visit(manifest.rootUrl);

        cy.findAllByTestId('submitted-application').should('have.length', 1);
        cy.findAllByTestId('submitted-application')
          .first()
          .should('contain.text', '%<lower_case_form>s');
        cy.injectAxe();
        cy.axeCheck();
      });

      it('should show a submission card with action needed indicator when status is error', () => {
        cy.intercept('GET', '/v0/my_va/submission_statuses', req => {
          req.reply({
            statusCode: 200,
            body: mockData('error'),
          });
        });
        cy.visit(manifest.rootUrl);

        cy.findAllByTestId('submitted-application').should('have.length', 1);
        cy.get('va-tag-status[status="error"]').should('have.attr', 'text', 'Action needed');
        cy.findAllByTestId('submitted-application')
          .first()
          .should('contain.text', '%<lower_case_form>s');
        cy.injectAxe();
        cy.axeCheck();
      });
    });

  TEXT

  # bundle exec rails runner lib/forms/scripts/add_new_form.rb METHOD=add_vets_website_e2e_tests
  # FORM=20-10206,21-0845-UPLOAD
  def add_vets_website_e2e_tests
    e2e_location = 'src/applications/personalization/dashboard/tests/e2e/benefit-applications-submitted.cypress.spec.js'
    e2e_file = File.join(vets_website_location, e2e_location)
    content = File.read(e2e_file)

    new_tests = form_ids.map do |form|
      format(E2E_TEMPLATE, form:, lower_case_form: form.downcase)
    end
    end_tag = '});'
    regex = /#{Regexp.escape(end_tag)}\Z/m
    replacement = "#{new_tests.join}\n#{end_tag}"
    replace_in_file(e2e_file, content, regex, replacement)
    system('yarn', 'eslint', '--fix', e2e_location.to_s, chdir: vets_website_location)
  end

  def process_inputs
    supported_methods = %w[add_all add_to_vets_api add_vets_api_integration_test add_to_vets_website_constants
                           add_vets_website_mocks add_vets_website_e2e_tests]
    raise "valid methods are #{supported_methods}" unless method.in?(supported_methods)

    send(method)
  end

  private

  def vets_website_location
    @vets_website_location ||= begin
      param_tag = 'VETS_WEBSITE='
      forms = ARGV.find { |arg| arg.start_with?(param_tag) }
      location = forms ? forms.gsub(param_tag, '') : Rails.root.join('..', 'vets-website')
      raise "vets-website not found at #{location}" unless Dir.exist?(location)

      location
    end
  end

  def method
    get_required_param('METHOD')
  end

  def form_ids
    @form_ids ||= begin
      ids = get_required_param('FORM')
      ids.split(',').map(&:strip)
    end
  end

  def validate_service!
    param_tag = 'SERVICE'
    service = get_required_param(param_tag)
    return if service.in?(['LBI'])

    error_message = "Service params #{service} is not currently supported." \
                    'Script only supports the LBI (Lighthouse Benefits Intake) service at this time'
    raise error_message
  end

  def get_required_param(param_tag)
    full_tag = "#{param_tag}="
    param = ARGV.find { |arg| arg.start_with?(param_tag) }
    raise "ERROR: required param #{param_tag} not specified" if param.blank?

    param_value = param.gsub(full_tag, '')
    raise "ERROR: required param #{param_tag} value not specified" if param_value.blank?

    param_value
  end

  def replace_in_file(file_path, content, regex, replacement)
    raise "Pattern not found in #{file_path}" unless content.match?(regex)

    content.gsub!(regex, replacement)
    File.write(file_path, content)
  end
end

AddNewForm.new.process_inputs
