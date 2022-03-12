#!/bin/bash

# unregister gitlab runners and reset gitlab configuration
function gitlab-config-reset {
  echo Cleanup: Unregister all gitlab runners
  gitlab-runner unregister --all-runners

  # only clear the configuration once runners are unregistered,
  # otherwise registered runners will be orphaned
  echo Cleanup: Reset gitlab configuration
  cp -f /opt/gitlab-runner/base-config.toml /home/gitlab-runner/.gitlab-runner/config.toml
}

# terminate and remove all docker-machine instances
function docker-machine-rm-all {
  local machines=$(docker-machine ls --quiet --format "\{\{ .Name \}\}")
  if [ ! -z "${machines}" ]; then
    echo Cleanup: Stop and remove all docker machines
    docker-machine stop ${machines}
    docker-machine rm --force -y ${machines}
  fi
}

gitlab-config-reset
docker-machine-rm-all

echo Init: Register gitlab runner
gitlab-runner register \
  --template-config /opt/gitlab-runner/gitlab-build.toml \
  --non-interactive \
  --url "https://gitlab.com" \
  --registration-token {{ gitlab_runner_registration_token }} \
  --executor "docker+machine" \
  --docker-image "bash:latest" \
  --shell "bash" \
  --tag-list "gitlab-build" \

# start gitlab-runner
#
# gitlab-runner binary doesn't seem to capture
# the signal sent by docker to stop a container,
# prevening cleanup. Workaround by capturing
# termination signals here and then killing the
# process ID of gitlab-runner.
echo Run: gitlab runner
gitlab-runner run &
gitlab_pid=$!
trap 'kill -INT ${gitlab_pid}' SIGINT SIGQUIT SIGTERM
wait "${gitlab_pid}" # block until service terminates
retval=$?

gitlab-config-reset
docker-machine-rm-all

exit ${retval}
