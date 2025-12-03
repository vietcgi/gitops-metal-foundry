# Tinkerbell Provisioning Workflow

## Problem: Re-provisioning Loop

Due to using ISC DHCP (not Smee DHCP), the `toggleAllowNetboot` feature and `allowPXE` settings in Hardware resources **do not affect DHCP boot behavior**. The ISC DHCP server will always serve PXE boot options to bare metal machines regardless of these settings.

## Solution: Manual Toggle Workflow

### Default State (in Git)
Hardware definitions should have PXE **disabled** by default:
```yaml
netboot:
  allowPXE: false
  allowWorkflow: false
```

### When You Need to Provision/Re-provision

1. **Enable PXE in Git**:
   ```bash
   # Edit hardware.yaml
   vim kubernetes/infrastructure/tinkerbell/hardware.yaml
   
   # Change to:
   netboot:
     allowPXE: true
     allowWorkflow: true
   
   # Commit and push
   git add kubernetes/infrastructure/tinkerbell/hardware.yaml
   git commit -m "temp: enable PXE for colo-server-01 reprovisioning"
   git push
   ```

2. **Apply the Workflow**:
   ```bash
   # Let Flux sync or manually reconcile
   ssh ubuntu@170.9.8.103 "flux reconcile kustomization infrastructure --with-source"
   
   # Create/apply the workflow
   kubectl apply -f kubernetes/infrastructure/tinkerbell/workflows.yaml
   ```

3. **Reboot the Server**:
   ```bash
   # Power cycle or reboot the bare metal machine
   ssh root@108.181.38.85 "reboot"
   # Or use IPMI/iDRAC to power cycle
   ```

4. **Monitor Progress**:
   ```bash
   ssh ubuntu@170.9.8.103 "kubectl get workflow colo-server-01-ubuntu -n tink-system -o wide"
   ```

5. **After Successful Provisioning - Disable PXE**:
   ```bash
   # Immediately disable PXE in Git
   vim kubernetes/infrastructure/tinkerbell/hardware.yaml
   
   # Change to:
   netboot:
     allowPXE: false
     allowWorkflow: false
   
   # Commit and push
   git add kubernetes/infrastructure/tinkerbell/hardware.yaml
   git commit -m "fix: disable PXE after successful provisioning"
   git push
   
   # Sync
   ssh ubuntu@170.9.8.103 "flux reconcile kustomization infrastructure --with-source"
   ```

6. **Delete the Workflow** (optional cleanup):
   ```bash
   ssh ubuntu@170.9.8.103 "kubectl delete workflow colo-server-01-ubuntu -n tink-system"
   ```

## Why Kexec Helps (Partially)

The `kexec-into-os` action boots directly into the installed OS kernel, bypassing BIOS/PXE for that **initial** boot. This allows the provisioning to complete successfully. However, if you manually reboot the server later, it will still try to PXE boot if `allowPXE: true` is still set in Git.

## Alternative: DHCP Configuration

You could also configure your ISC DHCP server to conditionally serve PXE only when needed, but that requires more complex DHCP configuration and external state management.
