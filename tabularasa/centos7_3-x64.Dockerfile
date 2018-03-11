FROM centos:7




INCLUDE lib/alpha
RUN yum update -y && yum install -y python python-devel curl gcc gcc-c++ make
RUN curl -L 'https://bootstrap.pypa.io/get-pip.py' | python





INCLUDE lib/omega
