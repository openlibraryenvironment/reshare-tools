# ReShare Docker Build

This code will automate the installation of a ReShare server.

- Creates a Docker container with a ssh user "user" and a specified password.
- Automatically installs all of the ReShare prerequisites (in the container).
- You need to have docker engine running on your host machine.
- This uses the concept "Docker in Docker" - where this Docker container will issue docker commands to the host docker environment.

## First steps

- Make sure your host machine is not using the following ports
  - 32
  - 80
  - 443
  - 5432
  - 9130-9230
- Clone this repo

  `git clone https://github.com/openlibraryenvironment/reshare-tools.git`

  `cd reshare-tools`
## How to use - Automatic method using reshare_ctl.pl

### Quick start

- let Perl know about this folder

`export PERL5LIB=/path/to/this/folder`

- Just do it

`./reshare_ctl --action start`

### More things about reshare_ctl.pl

This perl program will allow you to control the Docker stack easier.

- "--vars"

Specify a path to your custom vars file. Defaults to current working directory /vars.yml

- "--label"

Specify a label for the master Docker container. Defaults to "reshare-master-default". This feature allows you to create more master Docker containers that can run independently of one another.

- "--log"

This program writes a log file. You can direct it to a different path. Defaults to current working directory /log_reshare_ctl.log

- "--debug"

Flag. No input required. Flip this flag in order to get more verbose runtime output.

- "--action" options

  - start

As it would imply, "start" starts the ReShare server. This will automate the vars.yml file from the example file. If you've already customized your vars.yml file, it will use that. If you have not created your own vars.yml file it will create one from the example file. Your machine IP address will be auto-detected and configured. If the master container is already running, it will start the OKAPI service. If the container is not running but was* running, it will start the container from the stopped container. If a previous container doesn't exist, it will create one from the image. If an image doesn't exist, it will build the image from this directory.

  - stop

This will stop the OKAPI service running within the master container. It will then also stop the postgres server running in the master container (if postgres configured). And finally it will stop the master container. The container will not be deleted.

  - stopokapi

This will stop the OKAPI service running within the master container.

  - stopeverything

This will cause the software to loop through all of the **running** containers and stop them **and delete them**. It does not delete images.

  - rmi

This does everything that "stop" does, plus take the extra step and delete the master Docker image.

  - status

Not implemeted yet

  - change

Not implemeted yet

## How to use - manual method

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
- Once the docker image is built, take note of the image ID

## Start the final container and watch the console output
- **Make sure that you replace the Docker ID in the command below**
- **Make sure that you fill in the path for: /path/to/this/vars.yml**

  ``docker attach `docker run -itd --privileged  -p 80:80 -p 443:443 -p 9130:9130 -p 5432:5432 -p 32:22 -v /var/run/docker.sock:/var/run/docker.sock -v /path/to/this/vars.yml:/configs/vars.yml 2972d38b2b98` ``

- Alternatively without seeing the console output
    - **Make sure that you replace the Docker ID in the command below**
    - **Make sure that you fill in the path for: /path/to/this/vars.yml**

  `docker run -itd --privileged  -p 80:80 -p 443:443 -p 9130:9130 -p 5432:5432 -p 32:22 -v /var/run/docker.sock:/var/run/docker.sock -v /path/to/this/vars.yml:/configs/vars.yml 2972d38b2b98`

## Rejoice

You now have a working server. You can hit the server with a web browser:

  `http://<ip address>`
