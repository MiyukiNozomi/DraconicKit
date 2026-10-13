<script lang="ts">
  import { onMount } from "svelte";

  let props = $props<{ message: string }>();

  onMount(() => {});
</script>

<p style="color: white;">
  This is what the server gave us: {JSON.stringify(props)}
</p>
