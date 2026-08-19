import numpy as np
import json
from circadian.models import Forger99, Hannay19, Hannay19TP, Jewett99

dt = 0.1
t = np.arange(0.0, 72.0, dt)
# 16L/8D schedule: light on during hour-of-day in [8,24), off during [0,8)
lux = np.array([100.0 if (h % 24.0) >= 8.0 else 0.0 for h in t])

models = {
    "Forger99": Forger99(),
    "Hannay19": Hannay19(),
    "Hannay19TP": Hannay19TP(),
    "Jewett99": Jewett99(),
}

out = {}
for name, m in models.items():
    traj = m.integrate(t, input=lux)
    dlmo = m.dlmos(traj)
    out[name] = {
        "default_initial_condition": m._default_initial_condition.tolist(),
        "final_state_no_equilibrate": traj.states[-1].tolist(),
        "state_at_t24": traj(24.0).tolist(),
        "state_at_t48": traj(48.0).tolist(),
        "dlmos_no_equilibrate": dlmo.tolist(),
    }
    # equilibrate test (5 loops on a 24h window of same schedule)
    t24 = np.arange(0.0, 24.0, dt)
    lux24 = np.array([100.0 if (h % 24.0) >= 8.0 else 0.0 for h in t24])
    ic = m.equilibrate(t24, lux24, num_loops=5)
    out[name]["equilibrated_ic_5loops"] = ic.tolist()

with open("golden_vectors.json", "w") as f:
    json.dump(out, f, indent=2)

print(json.dumps(out, indent=2))
