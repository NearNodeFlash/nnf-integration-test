/*
 * Copyright 2023-2025 Hewlett Packard Enterprise Development LP
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package internal

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	dwsv1alpha7 "github.com/DataWorkflowServices/dws/api/v1alpha7"
	nnfv1alpha11 "github.com/NearNodeFlash/nnf-sos/api/v1alpha11"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/DataWorkflowServices/dws/utils/dwdparse"
)

const (
	helperImage = "ghcr.io/nearnodeflash/nnf-integration-test-helper"
)

var (
	// TestUserID and TestGroupID are the UID/GID used for workflow permissions in
	// container and data movement tests. These must correspond to a real user on the
	// system's compute/Rabbit nodes so that MPI SSH authentication is properly exercised.
	// Defaults to the flux user (1051/1052) since that is the WLM user that submits
	// MPI jobs in production. Using the mpiuser account (1050) would bypass the SSH key
	// setup code path where issue #310 occurs.
	// Override via NNF_USER_ID and NNF_GROUP_ID environment variables.
	TestUserID  uint32 = 1051
	TestGroupID uint32 = 1052
)

func init() {
	if s := os.Getenv("NNF_USER_ID"); s != "" {
		v, err := strconv.ParseUint(s, 10, 32)
		if err != nil {
			panic(fmt.Sprintf("invalid NNF_USER_ID '%s': %v", s, err))
		}
		TestUserID = uint32(v)
	}
	if s := os.Getenv("NNF_GROUP_ID"); s != "" {
		v, err := strconv.ParseUint(s, 10, 32)
		if err != nil {
			panic(fmt.Sprintf("invalid NNF_GROUP_ID '%s': %v", s, err))
		}
		TestGroupID = uint32(v)
	}
}

// VerifyUserOnRabbit creates a pod on a Rabbit node to verify that the given UID
// corresponds to a real user. This is important for MPI container tests: if the user
// doesn't exist on the system, SSH key setup follows a different code path and won't
// exercise the authentication flow that caused issue #310.
// Checks all Rabbit nodes in the system configuration.
func VerifyUserOnRabbit(ctx context.Context, k8sClient client.Client, uid uint32) {
	By(fmt.Sprintf("Verifying UID %d exists on the system", uid))

	systemConfig := GetSystemConfiguraton(ctx, k8sClient)

	var missing []string
	for _, storageNode := range systemConfig.Spec.StorageNodes {
		rabbitName := storageNode.Name
		podName := fmt.Sprintf("verify-uid-%d-%s", uid, rabbitName)
		privileged := true
		pod := &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{
				Name:      podName,
				Namespace: corev1.NamespaceDefault,
			},
			Spec: corev1.PodSpec{
				RestartPolicy: corev1.RestartPolicyNever,
				NodeName:      rabbitName,
				HostPID:       true,
				Containers: []corev1.Container{{
					Name:  "verify-uid",
					Image: "alpine:latest",
					// Use nsenter to run 'id' in the host's mount namespace so we
					// see the host's /etc/passwd rather than the container's.
					Command: []string{"nsenter", "-t", "1", "-m", "--", "id", fmt.Sprintf("%d", uid)},
					SecurityContext: &corev1.SecurityContext{
						Privileged: &privileged,
					},
				}},
			},
		}

		Expect(k8sClient.Create(ctx, pod)).To(Succeed())

		// Wait for pod to terminate
		Eventually(func(g Gomega) corev1.PodPhase {
			g.Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(pod), pod)).To(Succeed())
			return pod.Status.Phase
		}).WithTimeout(time.Minute).WithPolling(time.Second).Should(
			SatisfyAny(Equal(corev1.PodSucceeded), Equal(corev1.PodFailed)),
		)

		if pod.Status.Phase != corev1.PodSucceeded {
			missing = append(missing, rabbitName)
		}

		// Clean up the verification pod
		Expect(k8sClient.Delete(ctx, pod)).To(Succeed())
		WaitForDeletion(ctx, k8sClient, pod)

		By(fmt.Sprintf("Checked UID %d on Rabbit node '%s': found=%t", uid, rabbitName, pod.Status.Phase == corev1.PodSucceeded))
	}

	Expect(missing).To(BeEmpty(),
		fmt.Sprintf("UID %d does not exist on Rabbit node(s): %s. "+
			"MPI container tests require a real system user to properly exercise SSH authentication. "+
			"Set NNF_USER_ID and NNF_GROUP_ID environment variables to a valid user on the system.",
			uid, strings.Join(missing, ", ")))

	By(fmt.Sprintf("Verified UID %d exists on all %d Rabbit node(s)", uid, len(systemConfig.Spec.StorageNodes)))
}

func GetSystemConfiguraton(ctx context.Context, k8sClient client.Client) *dwsv1alpha7.SystemConfiguration {
	// TODO: Move this to a global variable and initialized in the test suite.
	// Note that putting the GET in Prepare will not work for things like
	// WithPersistentLustre() since those options run new MakeTests and do not
	// run prepare.

	systemConfig := &dwsv1alpha7.SystemConfiguration{}
	Expect(k8sClient.Get(ctx, types.NamespacedName{Name: "default", Namespace: corev1.NamespaceDefault}, systemConfig)).To(Succeed())

	// Except there to be at least 1 compute and storage node
	Expect(systemConfig.Computes()).ToNot(HaveLen(0))
	Expect(systemConfig.Spec.StorageNodes).ToNot(HaveLen(0))

	return systemConfig
}

func CurrentContext() (string, error) {
	out, err := exec.Command("kubectl", "config", "current-context").Output()
	return strings.TrimRight(string(out), "\r\n"), err
}

func GetVersion() (string, error) {
	out, err := exec.Command("./git-version-gen").Output()
	return strings.TrimRight(string(out), "\r\n"), err
}

// Start up a pod that accesses the global lustre filesystem and creates a file
// in the location specified by the copy_in directive.
func SetupCopyIn(ctx context.Context, k8sClient client.Client, t *T, o TOptions) {

	// remove global lustre filePath/ from the filepath
	filePath := strings.Replace(o.globalLustre.in, o.globalLustre.mountRoot+"/", "", 1)

	By("Starting copy-in pod and placing file(s) on global lustre")
	runHelperPod(ctx, k8sClient, t, "copy-in", "/copy-in.sh", []string{
		o.globalLustre.mountRoot,
		filePath,
		fmt.Sprintf("%d", t.workflow.Spec.UserID),
		fmt.Sprintf("%d", t.workflow.Spec.GroupID),
	})
}

// Start up a pod that accesses the global lustre filesystem and verifies that
// the files specified by the copy_in and copy_out directives match.
func VerifyCopyOut(ctx context.Context, k8sClient client.Client, t *T, o TOptions) {
	lus := t.options.globalLustre

	// Set numComputes to the number of compute nodes if index mount directories are expected.
	// Otherwise use 0 for lustre-lustre.
	numComputes := "0"
	if strings.Contains(lus.out, "*/") {
		numComputes = strconv.Itoa(len(t.computes.Data))
		lus.out = strings.ReplaceAll(lus.out, "*", "\\*") // escape the asterisk so bash doesn't glob
	}

	By("Starting copy-out pod and verifying copy out")
	runHelperPod(ctx, k8sClient, t, "copy-out", "/copy-out.sh", []string{
		lus.in,
		lus.out,
		numComputes,
	})
}

// Start up a pod with the given command/args and verify that it runs to completion
func runHelperPod(ctx context.Context, k8sClient client.Client, t *T, name, command string, args []string) {
	systemConfig := GetSystemConfiguraton(ctx, k8sClient)
	rabbitName := systemConfig.Spec.StorageNodes[0].Name
	o := t.options

	tag, err := GetVersion()
	Expect(err).ToNot(HaveOccurred())
	tag = strings.Replace(tag, "-dirty", "", 1)

	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      t.workflow.Name + "-" + name,
			Namespace: t.workflow.Namespace,
		},
		Spec: corev1.PodSpec{
			RestartPolicy: corev1.RestartPolicyNever,
			NodeName:      rabbitName,
			Containers: []corev1.Container{{
				Name:            name,
				Image:           fmt.Sprintf("%s:%s", helperImage, tag),
				ImagePullPolicy: corev1.PullAlways,
				Command: []string{
					command,
				},
				Args: args,
				VolumeMounts: []corev1.VolumeMount{{
					Name:      o.globalLustre.name,
					MountPath: o.globalLustre.mountRoot,
				}},
			}},
			Volumes: []corev1.Volume{{
				Name: o.globalLustre.name,
				VolumeSource: corev1.VolumeSource{
					PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
						ClaimName: fmt.Sprintf("%s-%s-readwritemany-pvc",
							o.globalLustre.name, t.workflow.Namespace),
					},
				},
			}},
		},
	}

	dwsv1alpha7.InheritParentLabels(pod, t.workflow)
	dwsv1alpha7.AddOwnerLabels(pod, t.workflow)
	dwsv1alpha7.AddWorkflowLabels(pod, t.workflow)

	Expect(k8sClient.Create(ctx, pod)).To(Succeed())
	t.helperPods = append(t.helperPods, pod)

	// Wait for successful completion
	Eventually(func(g Gomega) bool {
		g.Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(pod), pod)).To(Succeed())
		return pod.Status.Phase == corev1.PodSucceeded
	}).WithTimeout(time.Minute).WithPolling(time.Second).Should(BeTrue())
}

// HasContainerDirective returns true if this test includes a #DW container directive.
func (t *T) HasContainerDirective() bool {
	for _, directive := range t.directives {
		args, _ := dwdparse.BuildArgsMap(directive)
		if args["command"] == "container" {
			return true
		}
	}
	return false
}

// getPodLogs retrieves logs from a specific pod container using kubectl.
func getPodLogs(namespace, podName, containerName string) (string, error) {
	args := []string{"logs", podName, "-n", namespace}
	if containerName != "" {
		args = append(args, "-c", containerName)
	}
	out, err := exec.Command("kubectl", args...).CombinedOutput()
	return string(out), err
}

// sshErrorPatterns are log patterns indicating MPI SSH communication failures.
// See NearNodeFlash/NearNodeFlash.github.io#310.
var sshErrorPatterns = []string{
	"Permission denied",
	"ORTE was unable to reliably start one or more daemons",
}

// findContainerPods discovers container pods for a workflow. For MPI workflows,
// NNF_CONTAINER_LAUNCHER is set and NNF_CONTAINER_HOSTNAMES lists the launcher and
// worker hostnames. The MPI operator names worker pods exactly as the hostname, but
// the launcher pod has a random suffix (e.g. "workflow-launcher-xxxxx"), so we use
// prefix matching. For non-MPI containers, pods are found using owner labels.
func findContainerPods(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha7.Workflow) []*corev1.Pod {
	var result []*corev1.Pod

	Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(workflow), workflow)).To(Succeed())

	// Only MPI workflows have NNF_CONTAINER_LAUNCHER set. Non-MPI containers also
	// set NNF_CONTAINER_HOSTNAMES (with node names), so we must check LAUNCHER first.
	if _, isMPI := workflow.Status.Env["NNF_CONTAINER_LAUNCHER"]; isMPI {
		hostnames := workflow.Status.Env["NNF_CONTAINER_HOSTNAMES"]
		By(fmt.Sprintf("Found MPI container hostnames from workflow status: '%s'", hostnames))

		pods := &corev1.PodList{}
		Expect(k8sClient.List(ctx, pods, client.InNamespace(workflow.Namespace))).To(Succeed())

		// Build a set of hostnames for exact and prefix matching
		hostnameList := strings.Split(hostnames, ",")

		for i := range pods.Items {
			pod := &pods.Items[i]
			for _, hostname := range hostnameList {
				// Worker pods match exactly; launcher pods use the hostname as a prefix
				if pod.Name == hostname || strings.HasPrefix(pod.Name, hostname+"-") {
					result = append(result, pod)
					break
				}
			}
		}

		return result
	}

	// Fallback: find pods using owner labels (for non-MPI containers or if env isn't set)
	pods := &corev1.PodList{}
	Expect(k8sClient.List(ctx, pods, client.InNamespace(workflow.Namespace))).To(Succeed())

	for i := range pods.Items {
		pod := &pods.Items[i]
		// Check for NNF container label
		if _, ok := pod.Labels[nnfv1alpha11.ContainerLabel]; ok {
			if pod.Labels[dwsv1alpha7.WorkflowNameLabel] == workflow.Name ||
				pod.Labels[dwsv1alpha7.OwnerNameLabel] == workflow.Name {
				result = append(result, pod)
			}
		}
	}

	return result
}

// VerifyContainerPodLogs finds container pods for the given workflow and verifies
// their logs don't contain SSH authentication errors that indicate MPI communication
// failures. This catches issues like NearNodeFlash/NearNodeFlash.github.io#310 where
// mpirun fails with "Permission denied" when SSHing to worker nodes.
func VerifyContainerPodLogs(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha7.Workflow) {
	By("Verifying container pod logs for SSH errors")

	containerPods := findContainerPods(ctx, k8sClient, workflow)
	Expect(containerPods).NotTo(BeEmpty(), "expected to find container pods for workflow '%s' but found none", workflow.Name)

	for _, pod := range containerPods {
		By(fmt.Sprintf("Checking container pod '%s' (phase: %s)", pod.Name, pod.Status.Phase))

		// Get and check logs from all containers in the pod
		for _, container := range pod.Spec.Containers {
			logs, err := getPodLogs(pod.Namespace, pod.Name, container.Name)
			if err != nil {
				By(fmt.Sprintf("Warning: could not retrieve logs for pod '%s' container '%s': %v",
					pod.Name, container.Name, err))
				continue
			}

			for _, pattern := range sshErrorPatterns {
				Expect(logs).NotTo(ContainSubstring(pattern),
					fmt.Sprintf("SSH error detected in pod '%s' container '%s': found '%s' in logs.\n"+
						"This indicates an MPI communication failure (see NearNodeFlash/NearNodeFlash.github.io#310).\n"+
						"Logs:\n%s",
						pod.Name, container.Name, pattern, logs))
			}
		}
	}

	By(fmt.Sprintf("Verified %d container pod(s): no SSH errors found", len(containerPods)))
}

// ReportContainerPodLogs collects container pod logs for a workflow and returns
// them as a formatted string for inclusion in test failure reports.
func ReportContainerPodLogs(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha7.Workflow) string {
	if err := k8sClient.Get(ctx, client.ObjectKeyFromObject(workflow), workflow); err != nil {
		return fmt.Sprintf("Failed to get workflow: %v", err)
	}

	containerPods := findContainerPods(ctx, k8sClient, workflow)

	var sb strings.Builder
	for _, pod := range containerPods {
		sb.WriteString(fmt.Sprintf("\n--- Pod: %s (phase: %s) ---\n", pod.Name, pod.Status.Phase))
		for _, container := range pod.Spec.Containers {
			logs, err := getPodLogs(pod.Namespace, pod.Name, container.Name)
			if err != nil {
				sb.WriteString(fmt.Sprintf("  [%s] Error getting logs: %v\n", container.Name, err))
				continue
			}
			sb.WriteString(fmt.Sprintf("  [%s] Logs:\n%s\n", container.Name, logs))
		}
	}

	if sb.Len() == 0 {
		return "No container pods found"
	}
	return sb.String()
}

func CleanupHelperPods(ctx context.Context, k8sClient client.Client, t *T) {
	for _, p := range t.helperPods {
		By(fmt.Sprintf("Deleting helper pod %s", p.Name))
		Expect(k8sClient.Delete(ctx, p)).To(Succeed())
		WaitForDeletion(ctx, k8sClient, p)
	}
}

func WaitForDeletion(ctx context.Context, k8sClient client.Client, obj client.Object) {
	Eventually(func() error {
		return k8sClient.Get(ctx, client.ObjectKeyFromObject(obj), obj)
	}, "120s").Should(HaveOccurred(), fmt.Sprintf("object '%s' was not deleted", obj.GetName()))
}
