#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright © 2021 MOBIUS
# Blake Graham-Henderson <blake@mobiusconsortium.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ---------------------------------------------------------------


my @neededPorts = (80,443,9130,5432,32);
my $kafkaFullName = "wurstmeister/kafka";
my $zookeeperFullName = "wurstmeister/zookeeper";

use lib qw('./');

$SIG{INT} = \&cleanup;

# This is an attempt to make it easier on the user
# We will try to automatically install the required perl modules
# instead of asking them to do it :)

my @modules = qw (Getopt::Long Cwd File::Path File::Copy Data::Dumper Net::Address::IP::Local utf8 LWP JSON URI::Escape Data::UUID);

doModuleDance(\@modules);

our $url_id;
our $staff_url;
our $cwd = getcwd();
our $all = 0;
our $debug = 0;
our $action;  # start,stop,destroy
our $masterLabel = "reshare-master-default";

our %env;
our $log = "$cwd/log_reshare_ctl.log";
our $vars_file = "$cwd/vars.yml";
our $vars_file_example = "$cwd/vars.yml.example";
our $docker_file = "$cwd/Dockerfile";
our $docker_file_example = "$cwd/Dockerfile.example";
our $local_ip = Net::Address::IP::Local->public;


GetOptions (
"log=s" => \$log,
"debug" => \$debug,
"action=s" => \$action,
"vars=s" => \$vars_file,
"label=s" => \$masterLabel,
)
or die(help());

sub help
{
    print <<HELP;
$0
--action                  [Required: What this program should do: start, stop, stopokapi, stopeverything, change, rmi]
--debug                   [Not Required: switch on more verbosity on STDOUT and log]
--vars                    [Not Required: Path to your vars.yml file. Defaults to working dir/vars.yml]
--label                   [Not Required: an aribtrary name for the master docker image. Default: '$masterLabel']
--log                     [Not Required: A log file for this program to dump it's log. Defaults to working dir/log_reshare_ctl.log]
HELP
exit;
}


# go ahead and lowercase the input globally
$action = lc $action;

# Make sure the user supplied ALL of the options
help() if(!$log);
help() if(!$action);
help() if( ($action ne 'start') && !($action =~ m/stop/) && ($action ne 'change') && ($action ne 'status') && ($action ne 'rmi') && !($action =~ m/setup/) );

truncFile($log, '');

# Sanity check the vars file
checkVarsFile();

my $finishText = "\nAll Done";
if( $action eq 'start' )
{
    dealWithMasterImage($action);
}
elsif( $action eq 'stopeverything' )
{
    my $cmd = "docker ps --format \"{{.Image}}\"";
    my $ret = execSystemCMDWithReturn($cmd);
    my @ids = split(/\n/,$ret);
    my $list = "";
    $list .= "$_\n" foreach(@ids);
    promptUser(boxText("WARNING\nThis will stop and delete all of the running containers on your system.\nIncluding non-ReShare containers.\n\n$list\nYou can kill execution now if you don't like this idea"));
    stopAllContainers();
    $finishText = "All Containers have been stopped and deleted$finishText";
}
elsif( $action =~ m/stop/ )
{
    dealWithMasterImage($action);
    $finishText = "Master Container has been stopped$finishText";
}
elsif( $action =~ m/rmi/ )
{
    dealWithMasterImage($action);
    $finishText = "Master Container deleted$finishText";
}
elsif( $action =~ m/setup/ )
{
    dealWithSetupTestData($action);
    $finishText = "Installed Test Data$finishText";
}
else
{
   $finishText = "You need to specify a supported action: start, stop, stopokapi, stopeverything, rmi, change$finishText";
}

sleep 1;
errorOut(boxText($finishText,"#","!",8));

### End of main execution
### Sub routines are below

sub checkVarsFile
{
    if(-e $vars_file)
    {
        # Consume all those juicy variables
        %env = %{readConfig($vars_file)};
        errorOut("vars.yml does not specify an ip address (local_ip)") unless $env{"local_ip"};
        if($env{"local_ip"} ne $local_ip)
        {
            promptUser(
                boxText("NOTICE") .
                boxText(
                    "IP address config conflict\n".
                    "detected IP: '$local_ip'\n".
                    "vars.yml IP: '" . $env{"local_ip"} . "'\n"
                    ," ","|",2) . 
                    "You can cancel execution now or press enter to continue\n" , 0
            );
        }

    }
    elsif(!(-e $vars_file_example))
    {
        errorOut(boxText("Sorry, I can't find a vars.yml file nor the example file. Please specify a path to your vars.yml file"));
    }
    else
    {
        promptUser(
            boxText("vars.yml does not exist") .
            boxText(
                "I can create vars.yml with defaults.\n"
                ," ","|",2) . 
                "You can cancel execution now or press enter to continue\n" , 0
        );
        copyFile($vars_file_example, $vars_file);
        my $contents = editYML($local_ip,"local_ip",$vars_file,"replace");
        $contents =~ s/[\n\t]*$//g;
        truncFile($vars_file, $contents);
        undef $contents;
    }

    # Dockerfile variant
    if( !(-e $docker_file) )
    {
        if(!(-e $docker_file_example))
        {
            errorOut(boxText("Sorry, I can't find a Dockerfile file nor the example file."));
        }
        promptUser(
            boxText("Dockerfile does not exist") .
            boxText(
                "I can create Dockerfile with defaults.\n"
                ," ","|",2) . 
                "You can cancel execution now or press enter to continue\n" , 0
        );
        copyFile($docker_file_example, $docker_file);
    }
}

sub getDockerID
{
    my $search = shift;
    my $include_non_running = shift;
    my $image = shift; # search for Docker images rather than containers
    my $non_running_switch = '';
    $non_running_switch = "-a" if $include_non_running;
    my $cmd = "docker ps $non_running_switch -f name=\"$search\" --format \"{{.ID}}\"";
    $cmd = "docker images --format \"{{.ID}}\" --filter \"label=$masterLabel\"" if($image);
    my $id = execSystemCMDWithReturn($cmd);
    if($image && !$id)# maybe we are matching on repository name/Image name instead of label
    {
        my @cmds = ("docker images --format \"{{.Repository}} {{.ID}}\"","docker images --format \"{{.ID}} {{.ID}}\"");
        foreach(@cmds)
        {
            $cmd = $_;
            $id = execSystemCMDWithReturn($cmd);
            my @results = split(/\n/,$id);
            $id = 0;
            foreach(@results)
            {
                my ($repo, $tid) = split(/ /,$_);
                $id = $tid if ($repo eq $search);
            }
            last if $id;
        }
    }
    if(!$image && !$id)# maybe we are matching on repository name instead of names
    {
        $cmd = "docker ps $non_running_switch --format \"{{.Image}} {{.ID}}\"";
        $id = execSystemCMDWithReturn($cmd);
        my @results = split(/\n/,$id);
        $id = 0;
        foreach(@results)
        {
            my ($repo, $tid) = split(/ /,$_);
            $id = $tid if ($repo eq $search);
        }
    }
    print "Container '$search' is '$id'\n";
    return $id;
}

sub dealWithMasterImage
{
    my $do = shift;
    my $ignoreStopped = shift;
    # Figure out if an image is already built
    my $imageName = getDockerID($masterLabel, 0, 1);
    my $runningContainer = getDockerID($imageName);
    my $nonRunningContainer = getDockerID($imageName, 1);
    if($do eq 'start')
    {
        if(!$imageName)
        {
            promptUser(
                boxText(
                    "Docker image doesn't exist (yet)\n" .
                    "I'm about to create the Master Docker image: '$masterLabel'\n" .
                    "This can take up to 20 minutes but usually less than 10. FYI."
                )
            );
            my $cmd = "cd $cwd && docker build . --no-cache --label \"$masterLabel\"";
            execSystemCMD($cmd);
            $imageName = getDockerID($masterLabel, 0, 1);
            errorOut(boxText("I couldn't find the resulting Docker image. Hopefully there is some useful output above :(")) if(!$imageName);
        }
        my $kafkaRunning = getDockerID($kafkaFullName);
        my $kafkaNotRunning = getDockerID($kafkaFullName, 1);
        my $zookeeperRunning = getDockerID($zookeeperFullName);
        my $zookeeperNotRunning = getDockerID($zookeeperFullName, 1);
        if($runningContainer || $nonRunningContainer) # in either case, we're not making a new one from image
        {
            if($runningContainer) # Handle the case when the master container is already running
            {
                print "Master container is running\n";
                startContainer($kafkaFullName) if(!$kafkaRunning && $kafkaNotRunning);
                startContainer($zookeeperFullName) if(!$zookeeperRunning && $zookeeperNotRunning);
                my $cmd = "sh -c \"cd /configs && ".
                  "java -Dhost=" . $env{"local_ip"} . " ".
                  "-Dokapiurl='http://" . $env{"local_ip"} . ":9130' ".
                  "-Dport_end=9230 ".
                  "-Dstorage=postgres ".
                  "-Dpostgres_host=" . $env{"pg_host"} . " ".
                  "-Dpostgres_port=" . $env{"pg_port"} . " ".
                  "-Dpostgres_username=" . $env{"pg_okapi_user"} . " ".
                  "-Dpostgres_password=" . $env{"pg_okapi_pass"} . " ".
                  "-Dpostgres_database=" . $env{"pg_okapi_db"} . " ".
                  "-DdockerRegistries=\\\"[{}, {'registry': 'knowledgeintegration', 'serveraddress': 'docker.libsdev.k-int.com' }]\\\" " .
                  "-jar okapi/okapi-core/target/okapi-core-fat.jar dev > logs/okapi.log &\"";
                  execDockerCMD($imageName, $cmd, 1);
            }
            elsif($nonRunningContainer) # Handle the case when there was* a running master container, just needs started
            {
                print "Master container is not running but was running before\n";
                checkPorts();
                stopContainer($kafkaFullName, 1);
                stopContainer($zookeeperFullName, 1);
                startContainer($imageName); # Master container starts kafka and zookeeper
            }
        }
        elsif($imageName) # We have a master image but no container running or not running
        {
            print "Master container is not running and needs to be created\n";
            stopContainer($kafkaFullName, 1);
            stopContainer($zookeeperFullName, 1);
            my $cmd = 
            "docker run -d --privileged ".
            "-p 80:80 " .
            "-p 81:81 " .
            "-p 443:443 " .
            "-p 9130:9130 " .
            "-p 5432:5432 " .
            "-p 32:22 " .
            "-v /var/run/docker.sock:/var/run/docker.sock " .
            "-v $vars_file:/configs/vars.yml " .
            "-v /mnt/evergreen/docker/reshare/entrypoint.yml:/configs/entrypoint.yml " .
            "$imageName &";
            execSystemCMD($cmd, 1);
        }
    }
    elsif($do =~ /stop/ && !$runningContainer && !$ignoreStopped)
    {
        errorOut(boxText("Master Container is already stopped\nDoing nothing.\nMaybe you want to clean all the other* containers?\nTry --stopeverything"));
    }
    elsif($do eq 'stopokapi')
    {
        my $cmd = "sh -c \"ps -ef | /bin/grep jar | /bin/awk '{print \\\$2}' | xargs kill\"";
        execDockerCMD($imageName, $cmd, 1);
    }
    elsif($do eq 'stop')
    {
        my $cmd = "sh -c \"ps -ef | /bin/grep jar | /bin/awk '{print \\\$2}' | xargs kill\"";
        eval("execDockerCMD(\$imageName, \$cmd, 1);") if ($runningContainer); # There may or may not be a running process to kill, doesn't matter, just make sure it's dead
        $cmd = "/etc/init.d/postgresql stop";
        execDockerCMD($imageName, $cmd, 1) if ($runningContainer);
        stopContainer($kafkaFullName, 1);
        stopContainer($zookeeperFullName, 1);
        stopContainer($imageName);
    }
    elsif($do eq 'rmi')
    {
        promptUser(boxText("Ready to delete the built Master Container: '$imageName'\n?"));
        dealWithMasterImage("stop", 1);
        stopContainer($imageName, 1);
        my $cmd = "docker rmi $imageName";
        execSystemCMD($cmd);
    }
}

sub dealWithSetupTestData
{
    my $do = shift;
    my @tenants = ("dev1_tenant","dev2_tenant");
    my $cardinalJSON = '{ '.
    '"name":"Cardinal test Consortium", '.
    '"slug":"CARDINAL", '.
    '"foafUrl":"http://$local_ip/cardinal.json", '.
    '"url":"http://not.a.real.consortium/", '.
    '"type":"Consortium", '.
    '"members":[ '.
        ' { "memberOrg":"dev1"}, '.
        ' { "memberOrg":"dev2"} '.
    '], '.
    '"friends":[ '.
        '{ "foaf": "http://$local_ip:9130/_/invoke/tenant/dev1_tenant/directory/externalApi/entry/dev1" }, '.
        '{ "foaf": "https://$local_ip:9130/_/invoke/tenant/dev2_tenant/directory/externalApi/entry/dev2" } '.
    '] }';

    my $imageName = getDockerID($masterLabel, 0, 1);
    my $runningContainer = getDockerID($imageName);
    if($runningContainer)
    {
        foreach(@tenants)
        {
            my $tenant = $_;
            my $authtoken = loginOKAPI($tenant);
            if($authtoken)
            {
                print "Logged in!\n" if $debug;
            }
            else
            {
                promptUser(boxText("Couldn't get logged into $tenant. Check your vars.yml for correct admin login creds.") );
                exit;
            }
            if($do eq 'setuptestbranches')
            {
                $cardinalJSON =~ s/"/\\\\"/g;
                my $cmd = "sh -c \"echo $cardinalJSON > /usr/share/nginx/dev1/cardinal.json\"";
                execDockerCMD($imageName, $cmd, 1);
                sendConsortiumSetup($authtoken);
                
            }
            elsif($do eq 'setupserviceaccounts')
            {
                my %accountDef =
                (
                    'address' => "http://$local_ip:9130/_/invoke/tenant/$tenant/rs/externalApi/statistics",
                    'businessFunction' => "rs_stats",
                    'name' => "RS_STATS",
                    'status' => 'managed',
                    'type' => "http",
                    'id' => getNewUUID()
                );
                createDirectoryServiceAccount($authtoken, $tenant, \%accountDef);
                %accountDef =
                (
                    'address' => "http://$local_ip:9130/_/invoke/tenant/$tenant/rs/externalApi/iso18626",
                    'businessFunction' => "ill",
                    'name' => "ISO18626",
                    'status' => 'managed',
                    'type' => "iso18626",
                    'id' => getNewUUID()
                );
                createDirectoryServiceAccount($authtoken, $tenant, \%accountDef);
            }
            elsif($do eq 'setupinstitutions')
            {
                # my @serviceAccounts = @{getExistingDirectoryServiceAccounts($authtoken, $tenant)};
                getDirectoryRef($authtoken, $tenant, "DirectoryEntry.Type");
            }
        }
    }
    else
    {
        promptUser(boxText("Cannot find master container") );
    }
}

sub standardAuthHeader
{
    my $authtoken = shift;
    my $tenant = shift;

    my $header = [
        'X-Okapi-Tenant' => $tenant,
        'X-Okapi-Token' => $authtoken
        ];
    return $header;
}

sub sendConsortiumSetup
{
    my $authtoken = shift;
    my $tenant = shift;
    my $header = standardAuthHeader($authtoken, $tenant);
    
    my $cardinalURL = "http://$local_ip/cardinal.json";
    $cardinalURL = uri_escape($cardinalURL);
    my $url = "/directory/api/addFriend?friendUrl=$cardinalURL";
    my $answer = runHTTPReq($header,'', "GET", $url);
    print Dumper($answer);
    exit;
}

sub getExistingDirectoryServiceAccounts
{
    my $authtoken = shift;
    my $tenant = shift;
    my $header = standardAuthHeader($authtoken, $tenant);
    my $resp = runHTTPReq($header, undef, "GET", "/directory/service?filters=status.value=managed&perPage=100&sort=id");
    my $ret = decode_json($resp->content);
    return $ret;
}

sub createDirectoryServiceAccount
{
    my $authtoken = shift;
    my $tenant = shift;
    my $defRef = shift;
    my %def = %{$defRef};

    my $header = standardAuthHeader($authtoken, $tenant);

    my %options = %{getDirectoryServiceDropdownOptions($authtoken, $tenant)};

    while ( (my $key, my $option) = each(%options) )
    {
        while ( (my $defkey, my $defoption) = each(%def) )
        {
            if($defkey eq $key)  # we have a dropdown menu key that needs converted into the server ID equivalent.
            {
                my $convert = $defoption;
                my @list = @{$option};
                foreach(@list)
                {
                    my %menuItem = %{$_};
                    print "Checking '".$menuItem{"value"}."'\n" if $debug;
                    if($menuItem{"value"} eq $defoption)
                    {
                        $convert = $menuItem{"id"};
                        print "Converted '$defoption' to '$convert'\n" if $debug;
                    }
                }
                $def{$defkey} = $convert;
            }
        }
    }
    runHTTPReq($header, encode_json(\%def), "POST", "/directory/service");
}

sub getDirectoryServiceDropdownOptions
{
    my $authtoken = shift;
    my $tenant = shift;
    my $header = standardAuthHeader($authtoken, $tenant);
    my %dropdowns = 
    (
        'businessFunction' => "Service.BusinessFunction",
        'type' => "Service.Type"
    );
    my %ret = ();
    while ( (my $internal, my $querystring) = each(%dropdowns) )
    {
        $ret{$internal} = getDirectoryRef($authtoken, $tenant, $querystring);
    }
    return \%ret;
}

sub getDirectoryRef
{
    my $authtoken = shift;
    my $tenant = shift;
    my $type = shift;
    my $header = standardAuthHeader($authtoken, $tenant);
    my @ret = ();
    my $url = "/directory/refdata?filters=desc=$type";
    print "$url\n";
    my $response = runHTTPReq($header, undef, "GET", $url);
    my $stuff = decode_json($response->content);
    my @vals = @{$stuff};
    foreach(@vals)
    {
        if(%{$_}{"values"})
        {
            my @answers = @{%{$_}{"values"}};
            foreach(@answers)
            {
                push (@ret, $_);
            }
        }
    }
    return \@ret;
}

sub loginOKAPI
{
    my $tenant = shift;
    my $header = [
        'X-Okapi-Tenant' => $tenant
        ];
    my $user = {
        username => $env{"reshare_admin_user"},
        password => $env{"reshare_admin_password"}
        };
    my $answer = runHTTPReq($header, encode_json($user), "POST", "/authn/login");
    return $answer->header("x-okapi-token") if($answer->is_success);
    return 0;
}

sub runHTTPReq
{
    my $header = shift;
    my $payload = shift;
    my $type = shift;
    my $url = shift;
    push(@{$header}, ( 'Content-Type' => 'application/json', 'Accept' => 'application/json, text/plain') );
    my $okapi = "http://$local_ip:9130";
    my $ua = LWP::UserAgent->new();
    my $req = HTTP::Request->new($type, "$okapi$url", $header, $payload);
    return $ua->request($req);
}

sub checkPorts
{
    foreach(@neededPorts)
    {
        errorOut(boxText("The following port is being used on your system and we need it!\n$_")) if(isPortUsed($_));
    }
}

sub startContainer
{
    my $container_name = shift;
    my $container_id = getDockerID($container_name);
    return 1 if ( ($container_id && length($container_id) > 0));
    $container_id = getDockerID($container_name, 1);
    execSystemCMD( "docker start $container_id") if ( ($container_id && length($container_id) > 0));
    $container_id = getDockerID($container_name);
    errorOut(boxText("Couldn't get '$container_name' started.\nYou're going to have to fix this by hand")) if(!$container_id);
}

sub stopContainer
{
    my $container_name = shift;
    my $rm = shift;
    my $container_id = getDockerID($container_name);
    if($container_id) # Make sure there is a container to stop
    {
        execSystemCMD( "docker stop $container_id") if ( ($container_id && length($container_id) > 0));
        $container_id = getDockerID($container_name);
        errorOut(boxText("Couldn't kill '$container_name'. You're going to have to fix this by hand")) if($container_id);
    }
    if($rm)
    {
        $container_id = getDockerID($container_name, 1);
        execSystemCMD( "docker rm $container_id") if ( ($container_id && length($container_id) > 0));
    }
}

sub editYML
{
    my $value = shift;
    my $yml_path = shift;
    my $file = shift;
    my $dothis = shift;
    my @path = split(/\//,$yml_path);

    my @lines = @{readFile($file)};
    my $depth = 0;
    my $ret = '';
    while(@lines[0])
    {
        my $line = shift @lines;
        if(@path[0])
        {
            @path[0] =~ s/!!!/\//g;
            my $preceed_space = $depth * 2;
            my $exp = '\s{'.$preceed_space.'}';
            $exp = '[^\s#]' if $preceed_space == 0;
            # print "testing $exp\n";
            if($line =~ m/^$exp.*/)
            {
                if($line =~ m/^[\s\-]*@path[0].*/)
                {
                    $depth++;
                    if(!@path[1]) ## we have arrived at the end of the array
                    {
                        # print "replacing '$line'\n";
                        my $t = @path[0];
                        if( $dothis eq 'replace' )
                        {
                            $line =~ s/^(.*?$t[^\s]*).*$/\1 $value/g;
                        }
                        elsif( $dothis eq 'create' )
                        {
                            my $newline = "";
                            # print "preceed space = $preceed_space\n";
                            my $i = 0;
                            $newline.=" " while($i++ < $preceed_space);
                            # print "new line = '$newline'\n";
                            $newline.=$value;
                            # print "new line = '$newline'\n";
                            $line.="$newline";
                        }
                        elsif( $dothis eq 'delete' )
                        {
                            $line='';
                        }
                        # print "now: '$line'\n";
                    }
                    shift @path;
                }
            }
        }
        $line =~ s/[\n\t]*$//g;
        $ret .= "$line\n" if ($line ne '');
    }

    return $ret;
}

sub readConfig
{
    my %ret = ();
    my $ret = \%ret;
    my $file = shift;

    if( !(-e $file) )
    {
        print "$file file does not exist\n";
        return false;
    }

    my @lines = @{ readFile($file) };

    foreach my $line (@lines)
    {
        $line =~ s/\n//;  #remove newline characters
        my $cur = trim($line);
        my $len = length($cur);
        if($len>0)
        {
            if(substr($cur,0,1)ne"#")
            {
                my $Name, $Value;
                ($Name, $Value) = split (/\:/, $cur);
                $$ret{trim($Name)} = trim($Value);
            }
        }
    }
    while ((my $key, my $val) = each(%ret))
    {
        if($val =~ m/\{\{/)
        {
            my $refVar = $val;
            $refVar =~ s/^.*?\{\{\s*([^\s\}]*)\s?\}\}.*$/$1/g;
            $ret{$key} = $ret{$refVar} if($ret{$refVar});
        }
    }

    return \%ret;
}

sub trim
{
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

sub execSystemCMD
{
    my $cmd = shift;
    my $logit = shift;
    print "executing $cmd\n" if $debug;
    addLogLine($cmd) if $logit;
    system($cmd) == 0
        or die "system '$cmd' failed: $?";
}

sub execSystemCMDWithReturn
{
    my $cmd = shift;
    my $dont_trim = shift;
    my $ret;
    print "executing $cmd\n" if $debug;
    addLogLine($cmd);
    open(DATA, $cmd.'|');
    my $read;
    while($read = <DATA>)
    {
        $ret .= $read;
    }
    close(DATA);
    return 0 unless $ret;
    $ret = substr($ret,0,-1) unless $dont_trim; #remove the last character of output.
    return $ret;
}

sub execDockerCMD
{
    my $docker_name = shift;
    my $docker_cmd = shift;
    my $as_root = shift;
    my $docker_id = getDockerID($docker_name);
    my $root = "--user root";
    $root = '' if !$as_root;
    my $cmd = "docker exec $root $docker_id $docker_cmd";
    if($docker_id)
    {
        execSystemCMD($cmd) if $docker_id;
    }
    else
    {
        print "We've encountered a problem executing a command on docker: '$docker_name' . \nIt doesn't exist!\n";
        exit;
    }
}

sub promptUser
{
    my $prompt = shift;
    my $dontAddAnything = shift;
    print "$prompt\n";
    print "Press <enter> to contine\n" if $dontAddAnything ne '0';
    my $ret = <STDIN>;
    return $ret;
}

sub makeEvenWidth  #line, width
{
    my $ret;

    if($#_+1 !=2)
    {
        return;
    }
    $line = @_[0];
    $width = @_[1];
    #print "I got \"$line\" and width $width\n";
    $ret=$line;
    if(length($line)>=$width)
    {
        $ret=substr($ret,0,$width);
    }
    else
    {
        while(length($ret)<$width)
        {
            $ret=$ret." ";
        }
    }
    #print "Returning \"$ret\"\nWidth: ".length($ret)."\n";
    return $ret;

}

sub errorOut
{
    my $print = shift;
    print $print;
    print "\n";
    exit;
}

sub boxText
{
    my $text = shift;
    my $hChar = shift || '#';
    my $vChar = shift || '|';
    my $padding = shift || 4;
    my $ret = "";
    my $longest = 0;
    my @lines = split(/\n/,$text);
    length($_) > $longest ? $longest = length($_) : '' foreach(@lines);
    my $totalLength = $longest + (length($vChar)*2) + ($padding *2) + 2;
    my $heightPadding = ($padding / 2 < 1) ? 1 : $padding / 2;

    # Draw the first line
    my $i = 0;
    while($i < $totalLength)
    {
        $ret.=$hChar;
        $i++;
    }
    $ret.="\n";
    # Pad down to the data line
    $i = 0;
    while( $i < $heightPadding )
    {
        $ret.="$vChar";
        my $j = length($vChar);
        while( $j < ($totalLength - (length($vChar))) )
        {
            $ret.=" ";
            $j++;
        }
        $ret.="$vChar\n";
        $i++;
    }

    foreach(@lines)
    {
        # data line
        $ret.="$vChar";
        $i = -1;
        while($i < $padding )
        {
            $ret.=" ";
            $i++;
        }
        $ret.=$_;
        $i = length($_);
        while($i < $longest)
        {
            $ret.=" ";
            $i++;
        }
        $i = -1;
        while($i < $padding )
        {
            $ret.=" ";
            $i++;
        }
        $ret.="$vChar\n";
    }
    # Pad down to the last
    $i = 0;
    while( $i < $heightPadding )
    {
        $ret.="$vChar";
        my $j = length($vChar);
        while( $j < ($totalLength - (length($vChar))) )
        {
            $ret.=" ";
            $j++;
        }
        $ret.="$vChar\n";
        $i++;
    }
     # Draw the last line
    $i = 0;
    while($i < $totalLength)
    {
        $ret.=$hChar;
        $i++;
    }
    $ret.="\n";

}

sub doModuleDance
{
    my $modules = shift;
    my @modules = @{$modules};
    my $needToInstall = 0;
    my @notInstalled = ();
    my $list = "";
    foreach(@modules)
    {
        local $@;
        eval "use $_;";
        push(@notInstalled, $_) if $@;
        $list .= "$_\n" if $@;
    }
    if($#notInstalled > -1)
    {
        promptUser(boxText("This system does not have the required perl modules installed.\n$list\nAuto install?"));
        foreach(@notInstalled)
        {
            installModule($_);
            # Try again after it's been supposedly installed
            local $@;
            eval "use $_;";
            print "Please install the perl module:\n$_\n and try again\n" if $@;
            exit if $@;
        }
    }
}

sub isPortUsed
{
    my $port = shift;
    my $cmd = "netstat -nlt|grep $port";
    my $results = execSystemCMDWithReturn($cmd);
    my @lines = split(/\n/,$results);
    if ($results && ($results ne ''))
    {
        foreach(@lines)
        {
            # grab the fourth column
            my @cols = split(/\s/, $_);
            my $fourth = @cols[3];
            $fourth =~ s/[^:]*:(.*)$/$1/g;
            return 1 if($fourth eq $port);
        }
    }
    return 0;
}

sub installModule
{
    my $module = shift;
    my $cmd = "export PERL_MM_USE_DEFAULT=1 && /usr/bin/perl -MCPAN -e 'install \"$module\"'";
    print boxText("executing:\n$cmd","#","|",2);
    sleep 1;
    execSystemCMD($cmd, 0);
}

sub cleanup
{
    print "Caught kill signal, please don't kill me, I need to cleanup\ncleaning up....\n";
    sleep 1;
    if($action eq 'create' && $app{"local_username"} && length($app{"local_username"}) > 0)
    {
       
    }
    print "done\n";
    exit 0;
}

sub stopAllContainers
{
    my $cmd = "docker ps --format \"{{.Image}}\"";
    my $ret = execSystemCMDWithReturn($cmd);
    my @ids = split(/\n/,$ret);
    foreach(@ids)
    {
        stopContainer($_,1);
    }
}

sub truncFile
{
    my $file = shift;
    my $line = shift;
    open(OUTPUT, '> '.$file) or $ret=0;
    binmode(OUTPUT, ":utf8");
    print OUTPUT "$line\n";
    close(OUTPUT);
}


sub addLogLine
{
    my $line = shift;
    open(OUTPUT, '>> '.$log) or $ret=0;
    binmode(OUTPUT, ":utf8");
    print OUTPUT "$line\n";
    close(OUTPUT);
}

sub copyFile
{
    my $file = shift;
    my $destination = shift;
    return copy($file, $destination);
}

sub readFile
{
    my $file = shift;
    my $trys=0;
    my $failed=0;
    my @lines;
    #print "Attempting open\n";
    if(-e $file)
    {
        my $worked = open (inputfile, '< '. $file);
        if(!$worked)
        {
            print "******************Failed to read file*************\n";
        }
        binmode(inputfile, ":utf8");
        while (!(open (inputfile, '< '. $file)) && $trys<100)
        {
            print "Trying again attempt $trys\n";
            $trys++;
            sleep(1);
        }
        if($trys<100)
        {
            #print "Finally worked... now reading\n";
            @lines = <inputfile>;
            close(inputfile);
        }
        else
        {
            print "Attempted $trys times. COULD NOT READ FILE: $file\n";
        }
        close(inputfile);
    }
    else
    {
        print "File does not exist: $file\n";
    }
    return \@lines;
}

sub getNewUUID
{
    my $ug = Data::UUID->new;
    return lc $ug->create_str(); #lowercasing alphabetic characters
}

sub DESTROY
{
    exit;
}

