# G-coordinator Docker Compose Implementation Plan

## 1. Basic Policy

- Use `ubuntu:22.04` as the base OS.
- Run G-coordinator GUI as a Linux GUI application inside the container.
- Use the same Docker Compose setup from Windows, macOS, and Linux hosts.
- Use X11 forwarding as the initial GUI display method.
- Keep the structure extensible so a VNC/noVNC option can be added later if needed.

## 2. Files To Create

### `Dockerfile`

- Use Ubuntu 22.04 as the base image.
- Install Python 3.10, pip, git, Qt, X11, and OpenGL related packages.
- Clone the latest G-coordinator repository.
- Install Python dependencies from `requirements.txt`.
- Set the working directory to the G-coordinator `src` directory.
- Use `python3 main.py` as the default command.

### `docker-compose.yml`

- Pass the host `DISPLAY` value into the container.
- Mount `/tmp/.X11-unix` for X11 forwarding.
- Add a persistent workspace volume for user data.
- Set Qt/OpenGL environment variables needed for cross-platform GUI behavior.

### `.env.example`

- Provide host-specific `DISPLAY` examples.
- Include examples for Linux, macOS, and Windows.

### `README.md`

- Document startup steps for Linux, macOS, and Windows.
- Explain required X server setup.
- Add troubleshooting notes for common Qt/OpenGL/X11 issues.

## 3. Linux Host Support

Allow local Docker containers to access the host X server:

```bash
xhost +local:docker
```

Use the host `DISPLAY` value and mount the X11 socket:

```yaml
environment:
  - DISPLAY=${DISPLAY}
volumes:
  - /tmp/.X11-unix:/tmp/.X11-unix
```

Linux should be the first verification target because X11 forwarding is most direct there.

## 4. macOS Host Support

- Use XQuartz.
- Set:

```env
DISPLAY=host.docker.internal:0
```

- Enable network client connections in XQuartz.
- Use software rendering if Qt/OpenGL rendering is unstable:

```env
QT_X11_NO_MITSHM=1
LIBGL_ALWAYS_SOFTWARE=1
```

## 5. Windows Host Support

- Use VcXsrv or X410.
- Assume Docker Desktop with Linux containers.
- Set:

```env
DISPLAY=host.docker.internal:0.0
```

- For VcXsrv, start it with access control disabled.
- Use software rendering if Qt/OpenGL rendering is unstable:

```env
QT_X11_NO_MITSHM=1
LIBGL_ALWAYS_SOFTWARE=1
```

## 6. Candidate OS Packages

Install the following package set in the container:

```bash
python3
python3-pip
python3-venv
git
libgl1
libglib2.0-0
libxkbcommon-x11-0
libxcb-xinerama0
libxcb-cursor0
libxcb-icccm4
libxcb-image0
libxcb-keysyms1
libxcb-randr0
libxcb-render-util0
libxcb-shape0
libxcb-xfixes0
libxrender1
libxi6
libsm6
libxext6
libfontconfig1
```

## 7. Docker Compose Structure

Initial service design:

```yaml
services:
  gcoordinator:
    build: .
    environment:
      - DISPLAY=${DISPLAY}
      - QT_X11_NO_MITSHM=1
      - LIBGL_ALWAYS_SOFTWARE=1
    volumes:
      - /tmp/.X11-unix:/tmp/.X11-unix
      - ./workspace:/workspace
    working_dir: /opt/G-coordinator/src
```

## 8. Verification Steps

Build the image:

```bash
docker compose build
```

Run the application:

```bash
docker compose run --rm gcoordinator
```

Verify the following:

- The GUI window opens.
- A sample or user file can be opened.
- G-code export works.
- The same Compose setup can be used from Linux, macOS, and Windows after host X server setup.

## 9. Expected Risks

- PyQt5 GUI behavior depends on host X server configuration.
- OpenGL rendering may vary by host OS, GPU driver, and X server.
- On Windows and macOS, VNC/noVNC may be more stable than X11 forwarding.
- Cloning the latest repository at build time improves freshness but reduces reproducibility.
- A later phase should allow pinning G-coordinator to a tag or commit hash.

## 10. Recommended Implementation Phases

### Phase 1: Linux X11 Baseline

- Implement `Dockerfile`.
- Implement `docker-compose.yml`.
- Verify GUI startup on a Linux host using X11 forwarding.

### Phase 2: Cross-Platform Documentation

- Add `.env.example`.
- Add README instructions for Linux, macOS, and Windows.
- Document XQuartz, VcXsrv, and common troubleshooting steps.

### Phase 3: Optional VNC/noVNC Profile

- Add a Compose profile for browser-based GUI access if X11 forwarding is unstable.
- Keep X11 as the simplest baseline path.

### Phase 4: Reproducibility And Data Handling

- Add support for pinning G-coordinator by tag or commit.
- Improve persistent workspace handling.
- Add a simple smoke-test or startup verification path.
