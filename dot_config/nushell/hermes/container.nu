def get-container-engine [--podman] {
    if $podman {
        "podman"
    } else {
        $env.HERMES_CONTAINER_ENGINE | default "docker"
    }
}