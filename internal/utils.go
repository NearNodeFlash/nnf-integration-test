package internal

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	dwsv1alpha2 "github.com/DataWorkflowServices/dws/api/v1alpha2"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	helperImage = "ghcr.io/nearnodeflash/nnf-integration-test-helper"
)

func GetSystemConfiguraton(ctx context.Context, k8sClient client.Client) *dwsv1alpha2.SystemConfiguration {
	// TODO: Move this to a global variable and initialized in the test suite.
	// Note that putting the GET in Prepare will not work for things like
	// WithPersistentLustre() since those options run new MakeTests and do not
	// run prepare.

	systemConfig := &dwsv1alpha2.SystemConfiguration{}
	Expect(k8sClient.Get(ctx, types.NamespacedName{Name: "default", Namespace: corev1.NamespaceDefault}, systemConfig)).To(Succeed())

	// Except there to be at least 1 compute and storage node
	Expect(systemConfig.Spec.ComputeNodes).ToNot(HaveLen(0))
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

	By("Starting copy-out pod and verifying copy out")
	runHelperPod(ctx, k8sClient, t, "copy-out", "/copy-out.sh", []string{
		lus.in,
		lus.out,
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

	dwsv1alpha2.InheritParentLabels(pod, t.workflow)
	dwsv1alpha2.AddOwnerLabels(pod, t.workflow)
	dwsv1alpha2.AddWorkflowLabels(pod, t.workflow)

	Expect(k8sClient.Create(ctx, pod)).To(Succeed())
	t.helperPods = append(t.helperPods, pod)

	// Wait for successful completion
	Eventually(func(g Gomega) bool {
		g.Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(pod), pod)).To(Succeed())
		return pod.Status.Phase == corev1.PodSucceeded
	}).WithTimeout(time.Minute).WithPolling(time.Second).Should(BeTrue())
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
	}, "60s").Should(HaveOccurred(), fmt.Sprintf("object '%s' was not deleted", obj.GetName()))
}
