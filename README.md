# ReShare Docker Build

This code will automate the installation of a ReShare server.

- Creates a Docker container with a ssh user "user" and a specified password.
- Automatically installs all of the ReShare prerequisites (in the container).
- You need to have docker engine running on your host machine.
- This uses the concept "Docker in Docker" - where this Docker container will issue docker commands to the host docker environment.

## How to use

- Make sure your host machine is not using the following ports
  - 32
  - 80
  - 443
  - 5432
  - 9130-9230
- Clone this repo

  `git clone https://github.com/openlibraryenvironment/reshare-tools.git`

  `cd reshare-tools`

- Copy the default configs

  `cp Dockerfile.example Dockerfile`

  `cp vars.yml.example vars.yml`

- Edit vars.yml
At the very least, you need to supply the IP address of this computer
    - You might want to customize the SSH user password
    - You might want to customize the reshare admin login/password

  `vi vars.yml`

- Edit Dockefile (Optional)
  If you want to specify a timezone for the container, you do that here. Central time is default

  `vi Dockerfile`

- Build the container

  `docker build . --no-cache`

- The build procedure can take 10-20 minutes
- Once the container is built, take note of the container ID
- Start the final container and watch the console output
    - **Make sure that you replace the Docker ID in the command below**
    - **Make sure that you /path/to/this/vars.yml**

  ``docker attach `docker run -itd --privileged  -p 80:80 -p 443:443 -p 9130:9130 -p 5432:5432 -p 32:22 -v /var/run/docker.sock:/var/run/docker.sock -v /path/to/this/vars.yml:/configs/vars.yml 2972d38b2b98` ``

- Alternatively without seeing the console output
    - **Make sure that you replace the Docker ID in the command below**
    - **Make sure that you /path/to/this/vars.yml**

  `docker run -itd --privileged  -p 80:80 -p 443:443 -p 9130:9130 -p 5432:5432 -p 32:22 -v /var/run/docker.sock:/var/run/docker.sock -v /path/to/this/vars.yml:/configs/vars.yml 2972d38b2b98`

## Rejoice

You now have a working server. You can hit the server with a web browser:

  `http://<ip address>`
