# import json, subprocess

# broadcast_file = "broadcast/DeployNamesV1.s.sol/31/run-latest.json"

# with open(broadcast_file) as f:
#   data = json.load(f)

# receipts = []
# for tx_hash in data["pending"]:
#   result = subprocess.run(
#     ["cast", "rpc", "--rpc-url", "rsk_testnet", "eth_getTransactionReceipt", tx_hash],
#     capture_output=True, text=True
#   )
#   receipt = json.loads(result.stdout)
#   receipt["effectiveGasPrice"] = "0x0"
#   receipts.append(receipt)
#   print(f"Fetched {tx_hash[:10]}... status={receipt['status']}")

# data["receipts"] = receipts
# data["pending"] = []

# with open(broadcast_file, "w") as f:
#   json.dump(data, f, indent=2)

# print(f"\nDone — {len(receipts)} receipts written, pending cleared")



import json, subprocess, sys

broadcast_file = "broadcast/DeployNamesV1.s.sol/31/run-latest.json"
rpc_alias = "rsk_testnet"

with open(broadcast_file) as f:
  data = json.load(f)

if not data["pending"]:
  print("No pending transactions to patch")
  sys.exit(0)

receipts = data.get("receipts", [])
still_pending = []

for tx_hash in data["pending"]:
  receipt_result = subprocess.run(
    ["cast", "rpc", "--rpc-url", rpc_alias, "eth_getTransactionReceipt", tx_hash],
    capture_output=True, text=True
  )

  raw = receipt_result.stdout.strip()
  if raw == "null" or not raw:
    print(f"  {tx_hash[:10]}... still pending")
    still_pending.append(tx_hash)
    continue

  receipt = json.loads(raw)

  tx_result = subprocess.run(
    ["cast", "rpc", "--rpc-url", rpc_alias, "eth_getTransactionByHash", tx_hash],
    capture_output=True, text=True
  )
  tx = json.loads(tx_result.stdout)
  receipt["effectiveGasPrice"] = tx.get("gasPrice", "0x0")

  receipts.append(receipt)
  status = "ok" if receipt["status"] == "0x1" else "FAILED"
  print(f"  {tx_hash[:10]}... {status} gasPrice={receipt['effectiveGasPrice']}")

data["receipts"] = receipts
data["pending"] = still_pending

with open(broadcast_file, "w") as f:
  json.dump(data, f, indent=2)

print(f"\nPatched {len(receipts)} receipts, {len(still_pending)} still pending")