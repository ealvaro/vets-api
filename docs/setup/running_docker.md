# Running the app with Docker

First make sure to follow the common [base setup](https://va.ghe.com/software/vets-api/blob/master/README.md#Base%20setup).

## ClamAV Antivirus Configuration

### EKS

Prior to EKS, ClamAV (the virus scanner) was deployed in the same process as Vets API. With EKS, ClamAV has been extracted out into it’s own service. Locally you can see the docker-compose.yml config for clamav.

Note: Running clamav natively, as we did in Vets API master still needs to be configured. For the time being, please run via docker:

Please set the clamav intitalizer initializers/clamav.rb file to the following:

```ruby
if Rails.env.development?
  ENV['CLAMD_TCP_HOST'] = Settings.clamav.host
  ENV['CLAMD_TCP_PORT'] = Settings.clamav.port
end
```

### Mocking ClamAV Locally

There is an additional choice to "mock" a successful clamav response if you want to receive a quick scanning response for local development. If you choose this path, please set the clamav mock setting to true in the local settings.yml. This will mock the clamav response in the virus_scan code.

```ruby
clamav:
  mock: true
```

## GitHub Enterprise Authentication

Several gems in the `Gemfile` are sourced from private repositories on `va.ghe.com`. To install them during `docker-compose build`, you need to provide a Personal Access Token (PAT).

### Creating a PAT

1. Go to [https://va.ghe.com/settings/tokens](https://va.ghe.com/settings/tokens)
2. Click **Generate new token** (classic)
3. Give it a descriptive name (e.g., `vets-api local dev`)
4. Select the **`repo`** scope (required for accessing private repositories)
5. Set an expiration date and click **Generate token**
6. Copy the token — you won't be able to see it again
7. **Authorize for SSO:** Back on the tokens list, click the **Configure SSO** button next to your new token and authorize it for the `software` organization.

### Setting the environment variable

Add the following to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export BUNDLE_VA__GHE__COM="x-access-token:<YOUR_PAT>"
```

Then reload your shell by sourcing whichever file you edited:

```bash
source ~/.zshrc  # or source ~/.bashrc
```

> **Note:** Do not commit your token to the repository. The `docker-compose.yml` reads `BUNDLE_VA__GHE__COM` from your environment at build time — the token value is never stored in any tracked file.

> **Note:** If you see a `403` or `fatal: could not read Username for 'https://va.ghe.com'` error during `make build`, your PAT is either missing, expired, or lacks the `repo` scope.

> **Note:** GitHub Enterprise PATs automatically expire every 90 days. You will need to rotate your token regularly and update `BUNDLE_VA__GHE__COM` in your shell profile when it changes.

## VA certificates

The image needs VA's internal CA certificates in its trust store to make TLS connections to VA services, whose certificates are issued by VA's internal PKI rather than a public CA.

Most local development doesn't need them, because services are mocked (see [Betamocks](betamocks.md)). They matter when you talk to a real VA service, which from a developer machine means an SSM port-forward — see [Reaching a real VA service locally](#reaching-a-real-va-service-locally) below. Either end of such a tunnel presents a VA-Internal certificate: a service directly, or fwdproxy, whose own certificate is issued by VA's internal PKI rather than by the ELB CA in `config/ca-trust/fwdproxy.crt`.

There are three ways the certificates can get into the image.

### Fetch them from the GHE mirror (no ECR access needed)

`bin/fetch-va-certs` downloads the VA anchors into `config/ca-trust/`, authenticating with the same PAT you already set up for `bundle install`:

```bash
bin/fetch-va-certs
make rebuild
```

The certificates it writes are gitignored, and the `Dockerfile` copies anything in that directory into the image's trust store. This is the recommended path for local development.

### Use the `va-certs` image from ECR

This is the default, and how CI, review instances, staging, and production build: leaving the `CERTS_IMAGE` build arg unset resolves it to the `ARG CERTS_IMAGE` default at the top of the `Dockerfile`, which is the ECR image. Pulling it requires ECR access, which most application developers do not have. If you do, log in and pass `certs=ecr` — `make` opts out of the ECR image otherwise (see below):

```bash
# log in to AWS with credentials for ECR, then:
make rebuild certs=ecr
```

`certs=ecr` reads the pinned reference out of the `Dockerfile`, so it stays in step with what deployed builds use. Without ECR login the build stops at `load metadata … 401 Unauthorized`.

`certs=` accepts any image reference, so building the cert image yourself from [vsp-platform-va-certs](https://va.ghe.com/software/vsp-platform-va-certs) and passing `make rebuild certs=va-certs:local` also works. Be aware that its build ends by reading fwdproxy CA certificates from Parameter Store under `/dsva-vagov/fwdproxy/<env>/ca/`, which needs IAM permissions most developers don't have — the build fails at that step without them. Use `bin/fetch-va-certs` instead.

### Build without them

Every `make` target exports `CERTS_IMAGE=certs_none` (equivalently, `certs=none`), a stage in the `Dockerfile` that supplies an empty certificate directory, so `make build` succeeds with no ECR access and nothing configured. The image simply has no VA trust, and the build says so:

```
⚠ No VA-Internal CAs in this image: CERTS_IMAGE=certs_none and none found in config/ca-trust/.
⚠ TLS to any VA service will fail certificate verification — including a service
⚠ reached over an SSM port-forward, which presents a VA-Internal certificate.
⚠ Run bin/fetch-va-certs and rebuild to install the anchors without ECR access.
```

This is the right behavior for mocked development, and the warning is there so a TLS failure later is recognizable rather than mysterious.

> **Note:** The build decides between validating and warning based on whether VA-Internal certificates are actually present, from either source — so the first two paths both produce `✓ VA certificates installed and validated`. If none are present *and* `CERTS_IMAGE` is something other than `certs_none`, the build fails rather than producing an image that silently can't verify VA TLS. That is what keeps CI, review instances, staging, and production honest. CI and the deploy pipeline build the `Dockerfile` directly (`docker/build-push-action`, in `code_checks.yml` and `build.yml`) and pass no `CERTS_IMAGE`, so they get the ECR image from the `ARG` default; review instances pin it explicitly in `docker-compose.review.yml`. Only the `Makefile` opts out, and only for local development.

> **Note:** `CERTS_IMAGE=scratch` does not work. `scratch` has no filesystem, so copying certificates out of it fails the build with `lstat /usr/local/share/ca-certificates: no such file or directory`. Use `certs_none`.

## Reaching a real VA service locally

Deployed environments route outbound calls through fwdproxy. From a developer machine you get there with an SSM port-forward, then point the service's setting at the tunnel. Three details matter, and getting any of them wrong surfaces as a TLS or connection error rather than something obviously mis-configured.

**Keep the real hostname in the URL.** The certificate fwdproxy presents carries `DNS:*.vfs.va.gov` as its only SAN, so both `localhost` and `host.docker.internal` fail hostname verification even though the tunnel itself works.

**Map that hostname to the host gateway.** A container can't reach the Mac's loopback, where the tunnel listens. `docker-compose.override.yml` is gitignored and merged automatically:

```yaml
services:
  web:
    extra_hosts:
      - "fwdproxy-staging.vfs.va.gov:host-gateway"
  worker:
    extra_hosts:
      - "fwdproxy-staging.vfs.va.gov:host-gateway"
```

**Turn the service's mock off**, or Betamocks answers and nothing reaches the network. In `config/settings.local.yml` — also gitignored, so it's where a subscription key belongs:

```yaml
ppms:
  mock: false
  url: https://fwdproxy-staging.vfs.va.gov:4443
  api_keys:
    Ocp-Apim-Subscription-Key: <staging subscription key>
```

Settings changes need no rebuild, since the repo is bind-mounted into the container.

Confirm the trust path before booting the app. This uses the anchors `bin/fetch-va-certs` installs, so it also tells you whether those are in place:

```bash
cat config/ca-trust/VA-Internal-*.crt > /tmp/va.pem
openssl s_client -connect localhost:4443 -servername fwdproxy-staging.vfs.va.gov \
  -CAfile /tmp/va.pem -verify_hostname fwdproxy-staging.vfs.va.gov -verify_return_error </dev/null
```

`Verify return code: 0 (ok)` means tunnel, hostname, and trust store all line up. Interpreting what comes next:

| Symptom | Cause |
| --- | --- |
| `Connection refused` | The port-forward has lapsed — SSM sessions time out. Re-open it. |
| `certificate verify failed` | The image has no VA anchors (run `bin/fetch-va-certs` and rebuild), or the URL uses a hostname the certificate doesn't cover. |
| HTTP 401 | TLS and routing are fine; the subscription key is missing or wrong. |

## Makefile

A Makefile provides shortcuts for interacting with the docker images.

You can see all of the targets and an explanation of what they do with:

```bash
make help
```

To run vets-api and its redis and postgres dependencies run the following command from within the repo you cloned
in the above steps.

```bash
make up
```

You should then be able to navigate to [http://localhost:3000/v0/status](http://localhost:3000/v0/status) in your
browser and start interacting with the API. Changes to the source in your local
directory will be reflected automatically via a docker volume mount, just as
they would be when running rails directly.

The [Makefile](https://va.ghe.com/software/vets-api/blob/master/Makefile) has shortcuts for many common development tasks. You can still run manual [docker-compose commands](https://docs.docker.com/compose/),
but the following tasks have been aliased to speed development:

## Running tests

- `make spec` - Run the entire test suite via the docker image (alias for `rspec spec`). Test coverage statistics are in `coverage/index.html`.
- `make guard` - Run the guard test server that reruns your tests after files are saved. Useful for TDD!

## Running tests in parallel

- `make spec_parallel_setup` - This sets up the parallel tests databases. First the existing test database is dropped and reset, then the rest of the test databases are cloned off the standard one
- `make spec_parallel` - Run the entire test suite in parallel. A spec folder path can optionally be given as an argument to run just the spec folder in parallel

### Running pending tests

Pending or skipped tests are ignored by default, to run the test suite _with_ pending tests in the output, simply add the PENDING=true environment variable to the test command

`PENDING=true make spec_parallel`

### Running linters

- `make lint` - Run the full suite of linters on the codebase.
- `make security` - Run the suite of security scanners on the codebase.
- `make ci` - Run all build steps performed in CI.

### Running a rails interactive console

- `make console` - Is an alias for `rails console`, which runs an IRB like REPL in which all of the API's classes and
  environmental variables have been loaded.

### Running a bash shell

To emulate a local install's workflow where you can run `rspec`, `rake`, or `rails` commands
directly within the vets-api docker instance you can use the `make bash` command.

```bash
$ make bash
Creating network "vetsapi_default" with the default driver
Creating vetsapi_postgres_1 ... done
Creating vetsapi_redis_1    ... done
# then run any command as you would locally e.g.
root@63aa89d76c17:/src/vets-api# rspec spec/requests/user_request_spec.rb:26
```

### Troubleshooting

As a general technique, if you're running `vets-api` in Docker and run into a problem, doing a `make rebuild` is a good first step to fix configuration, gem, and other various code problems.

#### `make up` failing

Run `make build` and then try `make up` again.

#### `make up` fails with a message about missing gems

```bash
Could not find %SOME_GEM_v0.0.1% in any of the sources
Run `bundle install` to install missing gems.
```

There is no need to run `bundle install` on your system to resolve this.
A rebuild of the `vets_api` image will update the gems. The `vets_api` docker image
installs gems when the image is built, rather than mounting them into a container when
it is run. This means that any time gems are updated in the Gemfile or Gemfile.lock,
it may be necessary to rebuild the `vets_api` image using the
following command:

- `make down` - Stops all docker services.

- `make rebuild` - Rebuild the `vets_api` image.

- `make docker-clean` - Removes all docker images and volumes associated with vets-api.

Both `make build` and `make rebuild` accept `certs=` to choose which VA certificates go into the image — `certs=none` (the default), `certs=ecr`, or any image reference. See [VA certificates](#va-certificates) above.
