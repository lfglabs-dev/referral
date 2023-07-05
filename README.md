## Testing Cairo1 Contracts on Devnet

### Compile Contracts with Scarb :

Ensure your Scarb.toml file contains these settings:

```
[[target.starknet-contract]]
# Enable Sierra codegen.
sierra = true
# Enable CASM codegen.
casm = true
# Emit Python-powered hints in order to run compiled CASM class with legacy Cairo VM.
casm-add-pythonic-hints = true
# Specify which functions are allowed
allowed-libfuncs-list.name = "experimental_v0.1.0"
```

Build contracts with `scarb --release build` command.

### Run Devnet

Run the lastest version of the devnet using this command:

```
docker run -p 5050:5050 shardlabs/starknet-devnet:0.5.4 --disable-rpc-request-validation --seed 0 --timeout 5000 --compiler-args "--add-pythonic-hints --allowed-libfuncs-list-name experimental_v0.1.0"
```

### Run Scripts

You can now run your scripts in the script directory to declare, deploy and initialize contracts. Check `.env.example` file for env variables.
The script `deploy_devnet.py` will create create data to test indexer and endpoints.

Scripts work with version `0.17.0-alpha` of starknet.py.

## Indexing Contracts on Devnet using DNA

### Run DNA locally

Get latest version of DNA [here](https://github.com/apibara/dna)

From your DNA repo, run this command to run DNA locally:

```
OTEL_SDK_DISABLED=true RUST_LOG=info cargo run --release -p apibara-starknet -- start --devnet --rpc http://localhost:5050/rpc --wait-for-rpc
```

In your indexer repo, specify :

```

```

Then you should be good to go !
