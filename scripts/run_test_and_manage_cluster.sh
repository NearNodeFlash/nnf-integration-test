#!/bin/bash

# This script automates starting and stopping cluster services during a 'make test' run.
# It randomly selects nodes to fence during PreRun and manages services accordingly.

# --- Configuration ---
# All compute nodes available
ALL_NODES=(rabbit-compute-2 rabbit-compute-3 rabbit-compute-4 rabbit-compute-5)

# Map compute nodes to their rabbit nodes
# Function to get the rabbit node for a given compute node
get_rabbit_for_compute() {
    local compute_node="$1"
    case "$compute_node" in
        rabbit-compute-2) echo "rabbit-node-1" ;;
        rabbit-compute-3) echo "rabbit-node-1" ;;
        rabbit-compute-4) echo "rabbit-node-2" ;;
        rabbit-compute-5) echo "rabbit-node-2" ;;
        *) echo "" ;;
    esac
}

# Percentage of nodes to fence (0-100)
FENCE_PERCENTAGE=0

# The command to start the services
START_CMD='sudo systemctl start corosync pacemaker && sleep 5 && sudo pcs node unstandby'

# The command to stop the services
STOP_CMD='sudo pcs node standby && sudo systemctl stop pacemaker corosync'

# The absolute path to the clush command
# CLUSH_CMD="/Users/afloeder/dev2/nnf-deploy/nnf-integration-test/.venv/bin/clush"
CLUSH_CMD="clush"

# --- Randomly select nodes to fence (balanced across rabbits) ---
NUM_NODES=${#ALL_NODES[@]}
NUM_TO_FENCE=$(( NUM_NODES * FENCE_PERCENTAGE / 100 ))
if [ $NUM_TO_FENCE -eq 0 ] && [ $FENCE_PERCENTAGE -gt 0 ]; then
    NUM_TO_FENCE=1  # Fence at least one node if percentage > 0
fi

# Group nodes by rabbit
RABBIT1_NODES=()
RABBIT2_NODES=()
for node in "${ALL_NODES[@]}"; do
    rabbit=$(get_rabbit_for_compute "$node")
    if [ "$rabbit" = "rabbit-node-1" ]; then
        RABBIT1_NODES+=("$node")
    elif [ "$rabbit" = "rabbit-node-2" ]; then
        RABBIT2_NODES+=("$node")
    fi
done

# Calculate how many to fence from each rabbit (balance the load)
NUM_FROM_RABBIT1=$(( NUM_TO_FENCE / 2 ))
NUM_FROM_RABBIT2=$(( NUM_TO_FENCE - NUM_FROM_RABBIT1 ))

# If we need more from one rabbit than available, adjust
if [ $NUM_FROM_RABBIT1 -gt ${#RABBIT1_NODES[@]} ]; then
    NUM_FROM_RABBIT1=${#RABBIT1_NODES[@]}
    NUM_FROM_RABBIT2=$(( NUM_TO_FENCE - NUM_FROM_RABBIT1 ))
fi
if [ $NUM_FROM_RABBIT2 -gt ${#RABBIT2_NODES[@]} ]; then
    NUM_FROM_RABBIT2=${#RABBIT2_NODES[@]}
    NUM_FROM_RABBIT1=$(( NUM_TO_FENCE - NUM_FROM_RABBIT2 ))
fi

# Randomly select nodes from each rabbit
NODES_TO_FENCE=()
if [ $NUM_FROM_RABBIT1 -gt 0 ]; then
    NODES_TO_FENCE+=($(printf '%s\n' "${RABBIT1_NODES[@]}" | awk 'BEGIN{srand()}{print rand()"\t"$0}' | sort -n | cut -f2- | head -n $NUM_FROM_RABBIT1))
fi
if [ $NUM_FROM_RABBIT2 -gt 0 ]; then
    NODES_TO_FENCE+=($(printf '%s\n' "${RABBIT2_NODES[@]}" | awk 'BEGIN{srand()}{print rand()"\t"$0}' | sort -n | cut -f2- | head -n $NUM_FROM_RABBIT2))
fi

NODES_NOT_FENCED=($(printf '%s\n' "${ALL_NODES[@]}" "${NODES_TO_FENCE[@]}" | sort | uniq -u))

echo "=========================================="
echo "Fence Test Configuration:"
echo "=========================================="
echo "Total nodes: ${#ALL_NODES[@]}"
echo "  rabbit-node-1 nodes: ${RABBIT1_NODES[*]}"
echo "  rabbit-node-2 nodes: ${RABBIT2_NODES[*]}"
echo "Number to fence: $NUM_TO_FENCE (${FENCE_PERCENTAGE}%)"
echo "  From rabbit-node-1: $NUM_FROM_RABBIT1"
echo "  From rabbit-node-2: $NUM_FROM_RABBIT2"
echo "Nodes to fence: ${NODES_TO_FENCE[*]}"
echo "Nodes to manage normally: ${NODES_NOT_FENCED[*]}"
echo "=========================================="
echo

# Convert arrays to clush-compatible format
ALL_NODES_PATTERN=$(IFS=,; echo "${ALL_NODES[*]}")
FENCE_NODES_PATTERN=$(IFS=,; echo "${NODES_TO_FENCE[*]}")
NORMAL_NODES_PATTERN=$(IFS=,; echo "${NODES_NOT_FENCED[*]}")

# --- Script ---

echo "Starting 'make gfs2_fence' and monitoring for state changes..."

# Use process substitution to read from the 'make test' output line by line.
# The output of 'make test' is also sent to the terminal.
while IFS= read -r LINE; do
    echo "$LINE"
    
    # Check for the "DataIn" state - Start services on all nodes
    if echo "$LINE" | grep -q "Delaying in state DataIn"; then
        echo
        echo ">>> 'DataIn' state detected. Starting services on ALL nodes <<<"
        $CLUSH_CMD -w "$ALL_NODES_PATTERN" "$START_CMD"
        echo
    fi

    # Check for the "PreRun" state - Fence selected nodes
    if echo "$LINE" | grep -q "Delaying in state PreRun"; then
        echo
        echo "=========================================="
        echo ">>> 'PreRun' state detected. Fencing nodes! <<<"
        echo "=========================================="
        
        if [ ${#NODES_TO_FENCE[@]} -gt 0 ]; then
            # Fence each compute node via its rabbit
            for compute_node in "${NODES_TO_FENCE[@]}"; do
                rabbit_node=$(get_rabbit_for_compute "$compute_node")
                if [ -z "$rabbit_node" ]; then
                    echo "[ERROR] No rabbit mapping found for $compute_node, skipping..."
                    continue
                fi
                
                echo "[FENCE] Fencing $compute_node via $rabbit_node..."
                $CLUSH_CMD -w "$rabbit_node" "sudo pcs stonith fence $compute_node" &
            done
            
            # Wait for fencing operations to complete
            wait
            echo
            
            # Verify fencing occurred
            echo "[VERIFY] Checking fence history for fenced nodes..."
            for compute_node in "${NODES_TO_FENCE[@]}"; do
                rabbit_node=$(get_rabbit_for_compute "$compute_node")
                if [ -n "$rabbit_node" ]; then
                    echo "  History for $compute_node (via $rabbit_node):"
                    $CLUSH_CMD -w "$rabbit_node" "sudo pcs stonith history $compute_node | tail -10"
                fi
            done
            echo
            
            echo "[INFO] Fenced nodes will remain fenced"
            echo
            
            # Check node status from each rabbit
            echo "[STATUS] Checking cluster status from rabbits..."
            # Get unique rabbit nodes from the fenced compute nodes using simple deduplication
            unique_rabbits=""
            for compute_node in "${NODES_TO_FENCE[@]}"; do
                rabbit_node=$(get_rabbit_for_compute "$compute_node")
                if [ -n "$rabbit_node" ]; then
                    # Check if we've already added this rabbit
                    if ! echo "$unique_rabbits" | grep -q "$rabbit_node"; then
                        unique_rabbits="$unique_rabbits $rabbit_node"
                    fi
                fi
            done
            
            for rabbit_node in $unique_rabbits; do
                echo "  Status from $rabbit_node:"
                $CLUSH_CMD -w "$rabbit_node" "sudo pcs status nodes" | head -20
            done
            echo
        else
            echo "[INFO] No nodes selected for fencing in this run"
        fi
        
        echo "=========================================="
        echo
    fi

    # Check for the "DataOut" state - Stop services on non-fenced nodes only
    if echo "$LINE" | grep -q "Delaying in state DataOut"; then
        echo
        echo "=========================================="
        echo ">>> 'DataOut' state detected. Managing node services <<<"
        echo "=========================================="
        
        if [ ${#NODES_NOT_FENCED[@]} -gt 0 ]; then
            echo "[STOP] Stopping services on non-fenced nodes: ${NODES_NOT_FENCED[*]}"
            $CLUSH_CMD -w "$NORMAL_NODES_PATTERN" "$STOP_CMD"
        else
            echo "[INFO] All nodes were fenced, no services to stop"
        fi
        
        if [ ${#NODES_TO_FENCE[@]} -gt 0 ]; then
            echo "[INFO] Fenced nodes (${NODES_TO_FENCE[*]}) should be rebooting/recovering"
            echo "[CHECK] Checking if fenced nodes are back online..."
            for node in "${NODES_TO_FENCE[@]}"; do
                if ping -c 1 -W 2 "$node" &>/dev/null; then
                    echo "  ✓ $node is responding to ping"
                else
                    echo "  ✗ $node is still offline"
                fi
            done
        fi
        
        echo "=========================================="
        echo
    fi
done < <(make gfs2_fence 2>&1)

echo
echo "=========================================="
echo "Test finished."
echo "=========================================="
echo "Fenced nodes: ${NODES_TO_FENCE[*]:-none}"
echo "Normally managed nodes: ${NODES_NOT_FENCED[*]:-none}"
echo "=========================================="
