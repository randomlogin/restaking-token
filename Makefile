# include .env file and export its env vars
# (-include to ignore error if it does not exist)
# Note that any unset variables here will wipe the variables if they are set in
# .zshrc or .bashrc. Make sure that the variables are set in .env, especially if
# you're running into issues with fork tests
-include .env

deploy-lrt-local-test :; forge script script/foundry-scripts/DeployLRT.s.sol:DeployLRT --rpc-url localhost --private-key ${LOCAL_DEPLOYER_PRIVATE_KEY} --broadcast -vvv
