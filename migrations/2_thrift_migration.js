const ThriftManager = artifacts.require("ThriftManager");

module.exports = function(deployer) {
    deployer.deploy(ThriftManager);
}