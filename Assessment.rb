require 'cfndsl'

CloudFormation do
  Description 'Creates an AWS VPC with a 3 subnets - 1 Public and 2 Private subnets.'
  
  Parameter 'Environment' do
  Type 'String'
  Default  'Dev'
  AllowedValues %w(Dev Test)
  end
  
  Parameter 'vpcName' do
  Type 'String'
  Default  'Custom'
  end
  
  Parameter 'keyPairName' do
  Type 'String'
  Default  'demo'
  end
  
  Mapping('Dev', InstanceMap: { AmiId: 'ami-08935252a36e25f85', InstanceType: 't3.micro' })
  
  
  VPC(:DemoVPC) do
    EnableDnsSupport true
    EnableDnsHostnames true
    CidrBlock '10.0.0.0/16'
    add_tag('Name', Ref('vpcName'))
  end

  InternetGateway(:DemoInternetGateway) do
    add_tag('Name', 'Demo VPC Gateway')
  end
  
  EIP(:DemoEIP) do
        Domain 'vpc'
    end

  VPCGatewayAttachment(:GatewayToInternet) do
    VpcId Ref(:DemoVPC)
    InternetGatewayId Ref(:DemoInternetGateway)
  end

  3.times do |i|
	i=i+1
	pubsubnetcount = 1
	
	
	if i <= pubsubnetcount
    subnet = "pubsubnet#{i}"
	route_table = subnet + 'RouteTable'
    route_table_assoc = route_table + 'Assoc'
    Subnet(subnet) do
      VpcId Ref(:DemoVPC)
      CidrBlock "10.0.#{i*16}.0/20"
      add_tag('Name', "Demo vpc #{subnet}")
    end

    RouteTable(route_table) do
      VpcId Ref(:DemoVPC)
      add_tag('Name', route_table)
    end

    SubnetRouteTableAssociation(route_table_assoc) do
      SubnetId Ref(subnet)
      RouteTableId Ref(route_table)
    end

    Route(subnet + 'GatewayRoute') do
      DependsOn :GatewayToInternet
      RouteTableId Ref(route_table)
      DestinationCidrBlock '0.0.0.0/0'
      GatewayId Ref(:DemoInternetGateway)
    end
    if i == 1
    NatGateway(:DemoNATGateway) do
        AllocationId FnGetAtt(:DemoEIP, :AllocationId)
        SubnetId Ref(subnet)
    end
    end
	
	else
	subnet = "prvsubnet#{i}"
	route_table = subnet + 'RouteTable'
    route_table_assoc = route_table + 'Assoc'
    Subnet(subnet) do
      VpcId Ref(:DemoVPC)
      CidrBlock "10.0.#{i*16}.0/20"
      add_tag('Name', "Demo vpc #{subnet}")
    end

    RouteTable(route_table) do
      VpcId Ref(:DemoVPC)
      add_tag('Name', route_table)
    end

    SubnetRouteTableAssociation(route_table_assoc) do
      SubnetId Ref(subnet)
      RouteTableId Ref(route_table)
    end

    Route(subnet + 'GatewayRoute') do
      DependsOn :DemoNATGateway
      RouteTableId Ref(route_table)
      DestinationCidrBlock '0.0.0.0/0'
      NatGatewayId Ref(:DemoNATGateway)
    end
  end
  end
    
  
  Resource(:vpcSecurityGroup) do
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref(:DemoVPC))
    Property('GroupDescription', 'Allow required traffic')
    Property('SecurityGroupIngress', 
                   [
                    {
					"IpProtocol": "tcp",
					"FromPort": 22,
					"ToPort": 22,
					"CidrIp": "35.158.238.101/32"
                    }
                    ])
  end
  
  EC2_Instance(:DemoInstance) do
    ImageId FnFindInMap('Dev', :InstanceMap, :AmiId)
    Type FnFindInMap('Dev', :InstanceMap, :InstanceType)
    SecurityGroupIds [Ref('vpcSecurityGroup')]
    KeyName Ref('keyPairName') 
    SubnetId Ref('pubsubnet1')
	Volumes [
			  {
				"Device"   => "/dev/sdf",
				"VolumeId" => Ref("NewVolume")
			  }
			]
	UserData FnBase64(FnJoin("", [
							"#!/bin/bash -xe\n",
							"yum update -y\n",
							"# create mount point directory\n",
							"mkdir /mnt/app\n",
							"while [ ! -e /dev/xvdf ]; do echo waiting for /dev/xvdf to attach; sleep 10; done\n",
							"# create ext4 filesystem on new volume\n",
							"mkfs -t ext4 /dev/xvdf\n",
							"# add an entry to fstab to mount volume during boot\n",
							"echo \"/dev/xvdf       /mnt/app   ext4    defaults,nofail 0       2\" >> /etc/fstab\n",
							"# mount the volume on current boot\n",
							"mount -a\n"
						]))
	end
  
  Resource("NewVolume") do
    Type("AWS::EC2::Volume")
    Property("Size", "10")
    Property("AvailabilityZone", FnGetAtt(:pubsubnet1, :AvailabilityZone))
  end
  
  S3_Bucket('DemoBucket') do
	AccessControl 'Private' 
  end
  
  Output(:VpcId) do
    Description 'VPC Id'
    Value Ref(:DemoVPC)
  end
	
  Output(:SecurityGroup) do
    Description 'Security Group Id'
    Value Ref(:vpcSecurityGroup)
  end
  
  Output(:InstanceId) do
    Description 'Instance Id'
    Value Ref(:DemoInstance)
  end
  
  Output(:BucketName) do
    Description 'S3 bucket'
    Value Ref(:DemoBucket)
  end
  
end