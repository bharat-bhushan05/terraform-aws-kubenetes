module "vpc" {
    source = "./modules/vpc"
}

module "sec_group" {
    source = "./modules/sec_group"
    vpc_id = module.vpc.vpc_id
}

module "key_pair" {
    source = "./modules/key_pair"
}

module "ec2" {
    source       = "./modules/ec2"
    subnet_id    = module.vpc.subnet_id
    master_sg_id = module.sec_group.master_sg_id
    worker_sg_id = module.sec_group.worker_sg_id
    key_name     = module.key_pair.key_name
    private_key  = module.key_pair.private_key_pem
}