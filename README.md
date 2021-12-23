# ReShare Docker Build

This code will automate the installation of a ReShare server.

- Creates a Docker container with a ssh user "user" and a specified password.
- Automatically installs all of the ReShare prerequisites (in the container).
- You need to have docker engine running on your host machine.
- This uses the concept "Docker in Docker" - where this Docker container will issue docker commands to the host docker environment.
- This code will create two tenants: dev1_tenant and dev2_tenant.
- There are two OPAC's installed: http://<ip> (dev1) and http://<ip>:81 (dev2)

## Recommended Hardware

This software will create a full blown OKAPI server with all of Folio and Reshare modules on top. Roughly 30 Docker containers.

- I recommend at least 4 CPU's and 4GB of memory, but 8CPU, 8GB would be better :)

## First steps

- Make sure your host machine is not using the following ports
  - 32
  - 80
  - 81
  - 443
  - 5432
  - 9130-9230
- Clone this repo

  `git clone https://github.com/openlibraryenvironment/reshare-tools.git`

### Get Docker Installed

The default Ubuntu 20.04 Docker installation from the OS install wizard unfortunately installs the "snapd" version of Docker engine.

That doesn't play nice with this code. We need Docker to be running with a socket file on the filesystem so that we can share that with our Docker container.

This allows the Docker container to access the host Docker service.

- Don't let your OS install Docker automatically.
- Install Docker using docker.com install instructions: https://docs.docker.com/engine/install/ubuntu/
- Confirm that you have a docker socket file after the Docker service is running (AKA /var/run/docker.sock)

### Get Perl Modules installed

reshare_ctl.pl will attempt to install the required perl modules automatically, but you might want to install them yourself.

reshare_ctl.pl may not be able to install them automatically and you wlil need to install them yourself.

#### Required Perl Modules

- Getopt::Long
- Cwd
- File::Path
- File::Copy
- Data::Dumper
- Net::Address::IP::Local
- utf8
- LWP
- JSON
- URI::Escape
- Data::UUID

### Maybe customize vars.yml

reshare_ctl.pl will use the vars.yml.example file if vars.yml doesn't exist. It will also make an attempt to detect your host's IP address.

You will get feedback from the script while it's executing about this.

If you would like to make customizations, make a copy of the example:

`cp vars.yml.example vars.yml`


#### IP address

- edit vars.yml anda assign your host IP address for the variable: **local_ip** - if you don't, the perl script will attempt to figure it out

#### Timezone

- The timezone is setup inside the about-to-be-created Docker container.
- The definition for the timezone is located in **Dockerfile**

If **Dockerfile** doesn't exist, one will be created from a clone of **Dockerfile.example**

If you would like to use a different timezone other than the default (Central Time) then you will need to make your own **Dockerfile**

`cp Dockerfile.example Dockerfile`

For example edit **Dockerfile** and replace:

`RUN export DEBIAN_FRONTEND=noninteractive && ln -fs /usr/share/zoneinfo/America/Chicago /etc/localtime && apt-get install -y tzdata && dpkg-reconfigure --frontend noninteractive tzdata`

With

`RUN export DEBIAN_FRONTEND=noninteractive && ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime && apt-get install -y tzdata && dpkg-reconfigure --frontend noninteractive tzdata`


## Automatic method using reshare_ctl.pl

### Quick start

`cd reshare-tools`
`chmod 755 reshare_ctl.pl && ./reshare_ctl.pl --action start`

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

  - setupserviceaccounts

    The required service acconts will be automatically created. These are found in the interface Settings -> Directory -> Services.
    
    Currently, there are two hard-code defined service accounts: ISO18626 and RE_STATS. These will be created for both dev tenants (dev1, dev2)
    
    This does not work unless we can login to OKAPI. The configured reshare_admin_user and reshare_admin_password from vars.yml is used.

  - setupinstitutions

    Institutions cannot be created without first creating the Service Accounts (above).
    
    An institution will be created for each tenant: dev1 and dev2
    
    This does not work unless we can login to OKAPI. The configured reshare_admin_user and reshare_admin_password from vars.yml is used.

  - setupconsortium

    The consortium entry cannot be created without first creating the Institutions (above).
    
    A Consortium entry will be for each tenant: dev1 and dev2. The name of the consortium is "Cardinal"
    
    This does not work unless we can login to OKAPI. The configured reshare_admin_user and reshare_admin_password from vars.yml is used.

## Manual method

- This is not required if you use reshare_ctl.pl (previous section)
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

  For example edit **Dockerfile** and replace:

  `RUN export DEBIAN_FRONTEND=noninteractive && ln -fs /usr/share/zoneinfo/America/Chicago /etc/localtime && apt-get install -y tzdata && dpkg-reconfigure --frontend noninteractive tzdata`

  With

  `RUN export DEBIAN_FRONTEND=noninteractive && ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime && apt-get install -y tzdata && dpkg-reconfigure --frontend noninteractive tzdata`

- Build the container

  `docker build . --no-cache`

- The build procedure can take 10-20 minutes

- Once the docker image is built, take note of the image ID

### Start the final container and watch the console output

- This is not required if you use reshare_ctl.pl
- **Make sure that you replace the Docker ID in the command below**
- **Make sure that you fill in the path for: /path/to/this/vars.yml**

  ``docker attach `docker run -itd --privileged  -p 80:80 -p 81:81 -p 443:443 -p 9130:9130 -p 5432:5432 -p 32:22 -v /var/run/docker.sock:/var/run/docker.sock -v /path/to/this/vars.yml:/configs/vars.yml 2972d38b2b98` ``

- Alternatively without seeing the console output
    - **Make sure that you replace the Docker ID in the command below**
    - **Make sure that you fill in the path for: /path/to/this/vars.yml**

  `docker run -itd --privileged  -p 80:80 -p 81:81 -p 443:443 -p 9130:9130 -p 5432:5432 -p 32:22 -v /var/run/docker.sock:/var/run/docker.sock -v /path/to/this/vars.yml:/configs/vars.yml 2972d38b2b98`

## Rejoice

You now have a working server. You can hit the server with a web browser:

  - Dev1 Tenant: `http://<ip address>`
  - Dev2 Tenant: `http://<ip address>:81`
