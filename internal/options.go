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
	"path/filepath"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"go.openly.dev/pointy"
	"sigs.k8s.io/controller-runtime/pkg/client"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	dwsv1alpha2 "github.com/DataWorkflowServices/dws/api/v1alpha2"
	lusv1alpha1 "github.com/NearNodeFlash/lustre-fs-operator/api/v1alpha1"
	nnfv1alpha6 "github.com/NearNodeFlash/nnf-sos/api/v1alpha6"

	"github.com/DataWorkflowServices/dws/utils/dwdparse"
)

// TOptions lets you configure things prior to a test running or during test
// execution. Nil values represent no configuration of that type.
type TOptions struct {
	stopAfter           *TStopAfter
	expectError         *TExpectError
	storageProfile      *TStorageProfile
	containerProfile    *TContainerProfile
	persistentLustre    *TPersistentLustre
	mgsPool             *TMgsPool
	globalLustre        *TGlobalLustre
	cleanupPersistent   *TCleanupPersistentInstance
	duplicate           *TDuplicate
	hardwareRequired    bool
	lowTimeout          time.Duration
	highTimeout         time.Duration
	highTimeoutStates   []dwsv1alpha2.WorkflowState
	useExternalComputes bool
}

// Complex options that can not be duplicated
func (o *TOptions) hasComplexOptions() bool {
	return o.storageProfile != nil || o.containerProfile != nil || o.persistentLustre != nil || o.globalLustre != nil || o.cleanupPersistent != nil
}

type TStopAfter struct {
	state dwsv1alpha2.WorkflowState
}

// Stop after lets you stop a test after a given state is reached
func (t *T) StopAfter(state dwsv1alpha2.WorkflowState) *T {
	t.options.stopAfter = &TStopAfter{state: state}
	return t
}

type TExpectError struct {
	state dwsv1alpha2.WorkflowState
}

// Expect an error at the designed state; Proceed to teardown
func (t *T) ExpectError(state dwsv1alpha2.WorkflowState) *T {
	t.options.expectError = &TExpectError{state: state}
	t.options.stopAfter = &TStopAfter{state: state}
	return t.WithLabels("error")
}

func (t *T) ShouldTeardown() bool {
	if t.options.expectError != nil {
		return true
	}

	return t.options.stopAfter == nil
}

type TStorageProfile struct {
	name          string
	externalMgs   string
	standaloneMgt string
}

// WithStorageProfile will manage a storage profile of of name 'name'
func (t *T) WithStorageProfile() *T {

	for _, directive := range t.directives {
		args, _ := dwdparse.BuildArgsMap(directive)

		if args["command"] == "jobdw" || args["command"] == "create_persistent" {
			if name, found := args["profile"]; found {
				t.options.storageProfile = &TStorageProfile{name: name}
				return t.WithLabels("storage_profile", "storage-profile")
			}
		}
	}

	panic(fmt.Sprintf("profile argument required but not found in test '%s'", t.Name()))
}

func (t *T) WithStorageProfileStandaloneMGT(standaloneMGT string) *T {
	t.WithStorageProfile()
	t.options.storageProfile.standaloneMgt = standaloneMGT

	return t.WithLabels("standaloneMGT")
}

func (t *T) WithStorageProfileExternalMGS(externalMGS string) *T {
	t.WithStorageProfile()
	t.options.storageProfile.externalMgs = externalMGS

	return t.WithLabels("externalMGS")
}

// WithExternalComputes engages external computes for the the test.
func (t *T) WithExternalComputes() *T {
	t.options.useExternalComputes = true
	return t
}

type TContainerProfile struct {
	name    string
	base    string
	options *ContainerProfileOptions
}

type ContainerProfileOptions struct {
	PrerunTimeoutSeconds  *int
	PostrunTimeoutSeconds *int
	RetryLimit            *int
	NoStorage             bool // make any storages in the profile optional
}

func (t *T) WithContainerProfile(base string, options *ContainerProfileOptions) *T {
	for _, directive := range t.directives {
		args, _ := dwdparse.BuildArgsMap(directive)

		if args["command"] == "container" {
			if profile, found := args["profile"]; found {
				t.options.containerProfile = &TContainerProfile{name: profile, base: base, options: options}
				return t.WithLabels("container_profile", "container-profile")
			}
		}
	}

	panic(fmt.Sprintf("profile argument required but not found in test '%s'", t.Name()))
}

type TPersistentLustre struct {
	name     string
	capacity string

	// Use internal tests to drive the persistent lustre workflow
	create  *T
	destroy *T

	fsName  string
	mgsNids string
}

func (t *T) WithPersistentLustre(name string) *T {
	t.options.persistentLustre = &TPersistentLustre{name: name, capacity: "50GB"}
	return t.WithLabels("persistent", "lustre")
}

type TCleanupPersistentInstance struct {
	name string
}

// AndCleanupPersistentInstance will automatically destroy the persistent instance. It is useful
// if you have a create_persistent directive that you wish to destroy after the test has finished.
func (t *T) AndCleanupPersistentInstance() *T {
	for _, directive := range t.directives {
		args, _ := dwdparse.BuildArgsMap(directive)

		if args["command"] == "create_persistent" {
			t.options.cleanupPersistent = &TCleanupPersistentInstance{
				name: args["name"],
			}

			return t
		}
	}

	panic(fmt.Sprintf("create_persistent directive required but not found in test '%s'", t.Name()))
}

type TMgsPool struct {
	name  string
	count int
}

func (t *T) WithMgsPool(name string, count int) *T {
	t.options.mgsPool = &TMgsPool{name: name, count: count}
	return t.WithLabels("mgs_pool", "mgs-pool")
}

type TGlobalLustre struct {
	name       string
	mgsNids    string
	mountRoot  string
	namespaces map[string]lusv1alpha1.LustreFileSystemNamespaceSpec

	in  string // Create this file prior copy_in
	out string // Expect this file after copy_out

	persistent *TPersistentLustre // If using a persistent lustre instance as the global lustre
}

func (t *T) WithGlobalLustre(mountRoot string, fsName string, mgsNids string) {
	panic("reference to an existing global lustre instance is not yet supported")
}

// WithGlobalLustreFromPersistentLustre will create a global lustre file system from a persistent lustre file system
// namespaces can be added in addition to the default `nnf-dm-system`
func (t *T) WithGlobalLustreFromPersistentLustre(name string, namespaces []string) *T {
	if t.options.persistentLustre == nil {
		panic("Test option requires persistent lustre")
	}

	// Convert the slice of namespaces to LustreFilsystemNamespaceSpec map and add `nnf-dm-system` by default.
	lustreNamespaces := make(map[string]lusv1alpha1.LustreFileSystemNamespaceSpec)
	for _, ns := range append([]string{"nnf-dm-system"}, namespaces...) {
		lustreNamespaces[ns] = lusv1alpha1.LustreFileSystemNamespaceSpec{
			Modes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteMany},
		}
	}

	t.options.globalLustre = &TGlobalLustre{
		name:       "global-" + name,
		persistent: t.options.persistentLustre,
		mountRoot:  "/lus/" + name,
		namespaces: lustreNamespaces,
	}

	// For copy_in/copy_out, pull the source/destination paths and add them to global lustre
	var fsType string
	for _, directive := range t.directives {
		args, _ := dwdparse.BuildArgsMap(directive)

		if len(args["type"]) != 0 {
			fsType = args["type"]
		}

		if args["command"] == "copy_in" {
			if path, found := args["source"]; found {
				t.options.globalLustre.in = path
			}
		} else if args["command"] == "copy_out" {
			if path, found := args["destination"]; found {
				// Account for index mount directories in the path. This only works for file-file
				// data movement to assume where the '*' goes for the index mount directories.
				if fsType == "gfs2" || fsType == "xfs" {
					t.options.globalLustre.out = filepath.Join(filepath.Dir(path), "*", filepath.Base(path))
				} else {
					t.options.globalLustre.out = path
				}
			}
		}
	}

	return t.WithLabels("global_lustre", "global-lustre")
}

type TDuplicate struct {
	t     *T
	tests []*T
	index int
}

func (t *T) WithPermissions(userId, groupId uint32) *T {
	t.workflow.Spec.UserID = userId
	t.workflow.Spec.GroupID = groupId

	return t
}

// Prepare a test with the programmed test options.
func (t *T) Prepare(ctx context.Context, k8sClient client.Client) error {
	o := t.options

	// Skip the test if hardware is required and the current context includes "kind"
	if o.hardwareRequired {
		if context, err := CurrentContext(); err == nil {
			if strings.Contains(context, "kind") {
				Skip("This test cannot run in kind environment")
			}
		}
	}

	if o.storageProfile != nil {
		By(fmt.Sprintf("Creating storage profile '%s'", o.storageProfile.name))

		// Clone the default profile.
		defaultProf := &nnfv1alpha6.NnfStorageProfile{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "default",
				Namespace: "nnf-system",
			},
		}

		Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(defaultProf), defaultProf)).To(Succeed())

		profile := &nnfv1alpha6.NnfStorageProfile{
			ObjectMeta: metav1.ObjectMeta{
				Name:      o.storageProfile.name,
				Namespace: "nnf-system",
			},
		}

		defaultProf.Data.DeepCopyInto(&profile.Data)
		profile.Data.Default = false
		if o.storageProfile.externalMgs != "" {
			profile.Data.LustreStorage.CombinedMGTMDT = false
			profile.Data.LustreStorage.ExternalMGS = o.storageProfile.externalMgs
			profile.Data.LustreStorage.StandaloneMGTPoolName = ""
		} else if o.storageProfile.standaloneMgt != "" {
			profile.Data.LustreStorage.CombinedMGTMDT = false
			profile.Data.LustreStorage.ExternalMGS = ""
			profile.Data.LustreStorage.StandaloneMGTPoolName = o.storageProfile.standaloneMgt
		}

		Expect(k8sClient.Create(ctx, profile)).To(Succeed())
	}

	if o.containerProfile != nil {
		// Clone the provided base profile
		baseProfile := &nnfv1alpha6.NnfContainerProfile{
			ObjectMeta: metav1.ObjectMeta{
				Name:      o.containerProfile.base,
				Namespace: "nnf-system",
			},
		}

		Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(baseProfile), baseProfile)).To(Succeed())

		profile := &nnfv1alpha6.NnfContainerProfile{
			ObjectMeta: metav1.ObjectMeta{
				Name:      o.containerProfile.name,
				Namespace: "nnf-system",
			},
		}

		baseProfile.Data.DeepCopyInto(&profile.Data)

		// Override options
		if o.containerProfile.options != nil {
			opt := o.containerProfile.options
			if opt.PrerunTimeoutSeconds != nil {
				profile.Data.PreRunTimeoutSeconds = pointy.Int64(int64(*opt.PrerunTimeoutSeconds))
			}
			if opt.PostrunTimeoutSeconds != nil {
				profile.Data.PostRunTimeoutSeconds = pointy.Int64(int64(*opt.PostrunTimeoutSeconds))
			}
			if opt.RetryLimit != nil {
				profile.Data.RetryLimit = int32(*opt.RetryLimit)
			}
			if opt.NoStorage {
				for i, _ := range profile.Data.Storages {
					storage := &profile.Data.Storages[i]
					storage.Optional = true
				}
			}

		}

		Expect(k8sClient.Create(ctx, profile)).To(Succeed())
	}

	if o.cleanupPersistent != nil {
		// Nothing to do in Prepare()
	}

	if o.persistentLustre != nil {
		// Create a persistent lustre instance all the way to pre-run
		name := o.persistentLustre.name
		capacity := o.persistentLustre.capacity

		o.persistentLustre.create = MakeTest(name+"-create",
			fmt.Sprintf("#DW create_persistent type=lustre name=%s capacity=%s", name, capacity))
		o.persistentLustre.destroy = MakeTest(name+"-destroy",
			fmt.Sprintf("#DW destroy_persistent name=%s", name))

		// Create the persistent lustre instance
		By(fmt.Sprintf("Creating persistent lustre instance '%s'", name))
		Expect(k8sClient.Create(ctx, o.persistentLustre.create.Workflow())).To(Succeed())
		o.persistentLustre.create.Execute(ctx, k8sClient)

		// Extract the File System Name and MGSNids from the persistent lustre instance. This
		// assumes an NNF Storage resource is created in the same name as the persistent instance
		storage := &nnfv1alpha6.NnfStorage{
			ObjectMeta: metav1.ObjectMeta{
				Name:      name,
				Namespace: corev1.NamespaceDefault,
			},
		}

		By(fmt.Sprintf("Retrieving Storage Resource %s", client.ObjectKeyFromObject(storage)))
		Eventually(func(g Gomega) bool {
			g.Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(storage), storage)).To(Succeed())
			return storage.Status.Ready
		}).WithTimeout(time.Minute).WithPolling(time.Second).Should(BeTrue())

		o.persistentLustre.fsName = storage.Status.FileSystemName
		o.persistentLustre.mgsNids = storage.Status.MgsAddress
	}

	if o.mgsPool != nil {
		for i := 0; i < o.mgsPool.count; i++ {
			mgsPersistentStorage := MakeTest(fmt.Sprintf("MGS Pool %s-%d-create", o.mgsPool.name, i), fmt.Sprintf("#DW create_persistent type=lustre name=%s-%d profile=%s", o.mgsPool.name, i, o.mgsPool.name)).WithStorageProfileStandaloneMGT(o.mgsPool.name)

			By(fmt.Sprintf("Creating persistent lustre MGS '%s'", o.mgsPool.name))
			Expect(k8sClient.Create(ctx, mgsPersistentStorage.Workflow())).To(Succeed())
			mgsPersistentStorage.Prepare(ctx, k8sClient)
			mgsPersistentStorage.Execute(ctx, k8sClient)
			mgsPersistentStorage.Cleanup(ctx, k8sClient)

			Expect(k8sClient.Delete(ctx, mgsPersistentStorage.Workflow())).To(Succeed())
		}
	}

	if o.globalLustre != nil {

		lustre := &lusv1alpha1.LustreFileSystem{
			ObjectMeta: metav1.ObjectMeta{
				Name:      o.globalLustre.name,
				Namespace: corev1.NamespaceDefault,
			},
			Spec: lusv1alpha1.LustreFileSystemSpec{
				Name:       o.globalLustre.name,
				MgsNids:    o.globalLustre.mgsNids,
				MountRoot:  o.globalLustre.mountRoot,
				Namespaces: o.globalLustre.namespaces,
			},
		}

		if o.globalLustre.persistent != nil {
			lustre.Spec.Name = o.globalLustre.persistent.fsName
			lustre.Spec.MgsNids = o.globalLustre.persistent.mgsNids
		} else {
			panic("reference to an existing global lustre file system is not yet implemented")
		}

		By(fmt.Sprintf("Creating a global lustre file system '%s' @ '%s'", client.ObjectKeyFromObject(lustre), lustre.Spec.MountRoot))
		Expect(k8sClient.Create(ctx, lustre)).To(Succeed())

		// For our testing purposes, a copy_in directive assumes global lustre.
		// With this set, the source path will be created on the global lustre
		// filesystem
		if len(o.globalLustre.in) > 0 {
			SetupCopyIn(ctx, k8sClient, t, t.options)
		}
	}

	return nil
}

// Cleanup a test with the programmed test options. Note that the order in which test
// options are cleanup is the opposite order of their creation to ensure dependencies
// between options are correct.
func (t *T) Cleanup(ctx context.Context, k8sClient client.Client) error {
	o := t.options

	// Remove any helper pods that may have been used (e.g. copy_in, copy_out)
	if len(t.helperPods) > 0 {
		CleanupHelperPods(ctx, k8sClient, t)
	}

	// TODO: If a real lustre filesystem is used rather than persistent, we
	// should fire up another helper pod to delete copy_in/copy_out files (i.e.)
	// to.globalLustre.in/out. In the meantime, it is assumed the global lustre
	// is torn down.

	if o.globalLustre != nil {
		By(fmt.Sprintf("Deleting global lustre '%s'", o.globalLustre.name))
		lustre := &lusv1alpha1.LustreFileSystem{
			ObjectMeta: metav1.ObjectMeta{
				Name:      o.globalLustre.name,
				Namespace: corev1.NamespaceDefault,
			},
		}

		Expect(k8sClient.Delete(ctx, lustre)).To(Succeed())
		WaitForDeletion(ctx, k8sClient, lustre)
	}

	if o.mgsPool != nil {
		for i := 0; i < o.mgsPool.count; i++ {
			mgsPersistentStorage := MakeTest(fmt.Sprintf("MGS Pool %s-%d-destroy", o.mgsPool.name, i), fmt.Sprintf("#DW destroy_persistent name=%s-%d", o.mgsPool.name, i))

			By(fmt.Sprintf("Destroying persistent lustre MGS '%s'", o.mgsPool.name))
			Expect(k8sClient.Create(ctx, mgsPersistentStorage.Workflow())).To(Succeed())
			mgsPersistentStorage.Execute(ctx, k8sClient)
			mgsPersistentStorage.Cleanup(ctx, k8sClient)
			Expect(k8sClient.Delete(ctx, mgsPersistentStorage.Workflow())).To(Succeed())
			WaitForDeletion(ctx, k8sClient, mgsPersistentStorage.Workflow())
		}
	}

	if o.cleanupPersistent != nil {
		name := o.cleanupPersistent.name
		By(fmt.Sprintf("Destroying persistent filesystem '%s'", name))

		test := MakeTest(name+"-destroy", fmt.Sprintf("#DW destroy_persistent name=%s", name))
		Expect(k8sClient.Create(ctx, test.Workflow())).To(Succeed())
		test.Execute(ctx, k8sClient)
		Expect(k8sClient.Delete(ctx, test.Workflow())).To(Succeed())
		WaitForDeletion(ctx, k8sClient, test.Workflow())
	}

	if o.persistentLustre != nil {
		By(fmt.Sprintf("Deleting persistent lustre instance '%s'", o.persistentLustre.name))

		// Destroy the persistent lustre instance we previously created
		Expect(k8sClient.Create(ctx, o.persistentLustre.destroy.Workflow())).To(Succeed())
		o.persistentLustre.destroy.Execute(ctx, k8sClient)

		Expect(k8sClient.Delete(ctx, o.persistentLustre.create.Workflow())).To(Succeed())
		WaitForDeletion(ctx, k8sClient, o.persistentLustre.create.Workflow())

		Expect(k8sClient.Delete(ctx, o.persistentLustre.destroy.Workflow())).To(Succeed())
		WaitForDeletion(ctx, k8sClient, o.persistentLustre.destroy.Workflow())
	}

	if t.options.storageProfile != nil {
		By(fmt.Sprintf("Deleting storage profile '%s'", o.storageProfile.name))

		profile := &nnfv1alpha6.NnfStorageProfile{
			ObjectMeta: metav1.ObjectMeta{
				Name:      o.storageProfile.name,
				Namespace: "nnf-system",
			},
		}

		Expect(k8sClient.Delete(ctx, profile)).To(Succeed())
		WaitForDeletion(ctx, k8sClient, profile)
	}

	if t.options.containerProfile != nil {
		By(fmt.Sprintf("Deleting container profile '%s'", o.containerProfile.name))

		profile := &nnfv1alpha6.NnfContainerProfile{
			ObjectMeta: metav1.ObjectMeta{
				Name:      o.containerProfile.name,
				Namespace: "nnf-system",
			},
		}

		Expect(k8sClient.Delete(ctx, profile)).To(Succeed())
		WaitForDeletion(ctx, k8sClient, profile)
	}

	return nil
}
