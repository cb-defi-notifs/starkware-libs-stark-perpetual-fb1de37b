from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.dict_access import DictAccess

# Performs an efficient update of multiple leaves in a Merkle tree.
#
# Arguments:
# update_ptr - a list of DictAccess instances sorted by key (e.g., the result of squash_dict).
# height - the height of the merkle tree.
# prev_root - the value of the root before the update.
# new_root - the value of the root after the update.
#
# Hint arguments:
# preimage - a dictionary from the hash value of a merkle node to the pair of children values.
#
# Implicit arguments:
# hash_ptr - hash builtin pointer.
#
# Assumptions: The keys in the update_ptr list are unique and sorted.
# Guarantees: All the keys in the update_ptr list are < 2**height.
#
# Pseudocode:
# def diff(prev, new, height):
#   if height == 0: return [(prev,new)]
#   if prev.left==new.left: return diff(prev.right, new.right, height - 1)
#   if prev.right==new.right: return diff(prev.left, new.left, height - 1)
#   return diff(prev.left, new.left, height - 1) + \
#          diff(prev.right, new.right, height - 1)
func merkle_multi_update{hash_ptr : HashBuiltin*}(
        update_ptr : DictAccess*, n_updates, height, prev_root, new_root):
    if n_updates == 0:
        prev_root = new_root
        return ()
    end

    %{
        from starkware.python.merkle_tree import build_update_tree

        # Build modifications list.
        modifications = []
        for i in range(ids.n_updates):
          curr_update_ptr = ids.update_ptr.address_ + i * ids.DictAccess.SIZE
          modifications.append((
            memory[curr_update_ptr + ids.DictAccess.key],
            memory[curr_update_ptr + ids.DictAccess.new_value]))

        node = build_update_tree(ids.height, modifications)
        del modifications
        vm_enter_scope(dict(node=node, preimage=preimage))
    %}
    let orig_update_ptr = update_ptr
    with update_ptr:
        merkle_multi_update_inner(height=height, prev_root=prev_root, new_root=new_root, index=0)
    end
    assert update_ptr = orig_update_ptr + n_updates * DictAccess.SIZE
    %{ vm_exit_scope() %}
    return ()
end

# Helper function for merkle_multi_update().
func merkle_multi_update_inner{hash_ptr : HashBuiltin*, update_ptr : DictAccess*}(
        height, prev_root, new_root, index):
    let hash0 : HashBuiltin* = hash_ptr
    let hash1 : HashBuiltin* = hash_ptr + HashBuiltin.SIZE
    %{
        if ids.height == 0:
          assert node == ids.new_root, f'Expected node {ids.new_root}. Got {node}.'
          case = 'leaf'
        else:
          prev_left, prev_right = preimage[ids.prev_root]
          new_left, new_right = preimage[ids.new_root]

          left_child, right_child = node
          if left_child is None:
            assert right_child is not None, 'No updates in tree'
            case = 'right'
          elif right_child is None:
            case = 'left'
          else:
            case = 'both'

          # Fill non deterministic hashes.
          hash_ptr = ids.hash_ptr.address_
          memory[hash_ptr + 0 * ids.HashBuiltin.SIZE + ids.HashBuiltin.x] = prev_left
          memory[hash_ptr + 0 * ids.HashBuiltin.SIZE + ids.HashBuiltin.y] = prev_right
          memory[hash_ptr + 1 * ids.HashBuiltin.SIZE + ids.HashBuiltin.x] = new_left
          memory[hash_ptr + 1 * ids.HashBuiltin.SIZE + ids.HashBuiltin.y] = new_right

        memory[ap] = int(case != 'right')
    %}
    jmp not_right if [ap] != 0; ap++

    update_right:
    let hash_ptr = hash_ptr + 2 * HashBuiltin.SIZE
    prev_root = hash0.result
    new_root = hash1.result

    # Make sure the same authentication path is used.
    assert hash0.x = hash1.x

    # Call merkle_multi_update_inner recursively.
    %{ vm_enter_scope(dict(node=right_child, preimage=preimage)) %}

    merkle_multi_update_inner(
        height=height - 1, prev_root=hash0.y, new_root=hash1.y, index=index * 2 + 1)
    %{ vm_exit_scope() %}
    return ()

    not_right:
    %{ memory[ap] = int(case != 'left') %}
    jmp not_left if [ap] != 0; ap++

    update_left:
    let hash_ptr = hash_ptr + 2 * HashBuiltin.SIZE
    prev_root = hash0.result
    new_root = hash1.result

    # Make sure the same authentication path is used.
    assert hash0.y = hash1.y

    # Call merkle_multi_update_inner recursively.
    %{ vm_enter_scope(dict(node=left_child, preimage=preimage)) %}
    merkle_multi_update_inner(
        height=height - 1, prev_root=hash0.x, new_root=hash1.x, index=index * 2)
    %{ vm_exit_scope() %}
    return ()

    not_left:
    jmp update_both if height != 0

    update_leaf:
    # Note: height may underflow, but in order to reach 0 (which is verified here), we will need
    # more steps than the field characteristic. The assumption is that it is not feasible.

    # Write the update.
    %{ assert case == 'leaf' %}
    index = update_ptr.key
    prev_root = update_ptr.prev_value
    new_root = update_ptr.new_value
    let update_ptr = update_ptr + DictAccess.SIZE

    # Return values.
    return ()

    update_both:
    # When the function starts we have fp=ap.
    # The two nondeterministic jumps, write to [fp] and [fp + 1] and advances ap by 2.
    # Thus, the next free memory cell is [fp + 2] and we need to increment ap by 1.
    let local_left_index = [fp + 2]
    %{ assert case == 'both' %}
    local_left_index = index * 2; ap++

    let hash_ptr = hash_ptr + 2 * HashBuiltin.SIZE
    prev_root = hash0.result
    new_root = hash1.result

    # Update left.
    %{ vm_enter_scope(dict(node=left_child, preimage=preimage)) %}
    merkle_multi_update_inner(
        height=height - 1, prev_root=hash0.x, new_root=hash1.x, index=local_left_index)
    %{ vm_exit_scope() %}

    # Update right.
    # Push height to workaround one hint per line limitation.
    tempvar height_minus_1 = height - 1
    %{ vm_enter_scope(dict(node=right_child, preimage=preimage)) %}
    merkle_multi_update_inner(
        height=height_minus_1, prev_root=hash0.y, new_root=hash1.y, index=local_left_index + 1)
    %{ vm_exit_scope() %}
    return ()
end
