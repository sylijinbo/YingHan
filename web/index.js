var app = new Vue({
  el: "#app",
  data: {
    loading: false,
    subLoading: false,
    saveStatus: "",
    newKey: "",
    newValue: "",
    preference: {
      showTranslation: true,
      commitWordWithSpace: true,
      enableNextWordPrediction: false,
      candidatePanelLayout: "vertical",
      enableLeftShiftModeSwitch: false,
      enableRightShiftModeSwitch: true,
      enableLeftCommandPinyinSwitch: false,
      enableRightCommandPinyinSwitch: false
    },
    substitutions: {}
  },
  methods: {
    getPreference() {
      fetch("/preference")
        .then(function(res) {
          return res.json();
        })
        .then(preference => {
          this.preference = preference;
        });
    },
    updatePreference() {
      this.loading = true;
      this.saveStatus = "";
      fetch("/preference", {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        body: JSON.stringify(this.preference)
      })
        .then(function(res) {
          return res.json();
        })
        .then(preference => {
          this.preference = preference;
          this.loading = false;
          this.saveStatus = "Saved";
        })
        .catch(() => {
          this.loading = false;
          this.saveStatus = "Save failed";
        });
    },
    loadSubstitutions() {
      fetch("/substitutions")
        .then(function(res) {
          return res.json();
        })
        .then(data => {
          this.substitutions = data;
        });
    },
    addSubstitution() {
      if (!this.newKey || !this.newValue) return;
      this.subLoading = true;
      fetch("/substitutions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ key: this.newKey, value: this.newValue })
      })
        .then(function(res) {
          return res.json();
        })
        .then(data => {
          this.substitutions = data;
          this.newKey = "";
          this.newValue = "";
          this.subLoading = false;
        })
        .catch(() => {
          this.subLoading = false;
        });
    },
    removeSubstitution(key) {
      this.subLoading = true;
      fetch("/substitutions/" + encodeURIComponent(key), {
        method: "DELETE"
      })
        .then(function(res) {
          return res.json();
        })
        .then(data => {
          this.substitutions = data;
          this.subLoading = false;
        })
        .catch(() => {
          this.subLoading = false;
        });
    }
  }
});

app.getPreference();
app.loadSubstitutions();
