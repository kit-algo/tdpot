#!/usr/bin/env python3

import numpy as np
import matplotlib as mpl
from matplotlib import pyplot as plt
import seaborn as sns
sns.set()
import pandas as pd

import json
import glob
import os
import re

base = "exp/"
paths = glob.glob(base + "compression_par/*.json")
data = [json.load(open(path)) for path in paths]

runs = pd.DataFrame.from_records(data)
runs['merge'] /= 1000
baseline = runs.loc[lambda x: x['num_threads'] == 1]['merge'].mean()
runs['speedup'] = baseline / runs['merge']
runs['efficiency'] = runs['speedup'] / runs['num_threads']

fig, axs = plt.subplots(1, 2, figsize=(11,4))

g = sns.barplot(data=runs, x='num_threads', y='merge', hue='program', ax=axs[0]) 
g.legend_.remove()
g.set_xlabel('# Threads')
g.set_ylabel('Running time [s]')

g = sns.lineplot(data=runs, x='num_threads', y='efficiency', ci=None, ax=axs[1]) 
g.set(ylim=(-0.1, 1.1))
g.set_xlabel('# Threads')
g.set_ylabel('Efficiency')
g.set_xscale('log')
g.xaxis.set_major_locator(mpl.ticker.LogLocator(base=2,numticks=6))
g.xaxis.set_major_formatter(mpl.ticker.FuncFormatter(lambda val, pos: f"{int(val)}"))

plt.tight_layout()
g.get_figure().savefig('paper/fig/parallelization.pdf')
