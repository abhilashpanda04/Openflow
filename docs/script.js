// Openflow Website Interactions

document.addEventListener('DOMContentLoaded', () => {
  // 1. Gallery Tabs
  const tabBtns = document.querySelectorAll('.tab-btn');
  const panes = document.querySelectorAll('.gallery-pane');

  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-target');

      tabBtns.forEach(b => b.classList.remove('active'));
      panes.forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      const targetPane = document.getElementById(targetId);
      if (targetPane) {
        targetPane.classList.add('active');
      }
    });
  });

  // 2. Interactive Typing Simulation
  const transcriptEl = document.getElementById('demo-text');
  const demoStatus = document.getElementById('demo-status-text');
  const soundWave = document.getElementById('demo-sound-wave');

  const demoScenarios = [
    {
      text: "Hey team, just pushed the CoreML Whisper build. It runs 100% locally on Apple Silicon Neural Engine with zero cloud latency.",
      action: "Direct text injection into active app"
    },
    {
      text: "Let's deploy version 2.4 scratch that let's ship Openflow version 0.1.0 today.",
      action: "Auto-corrected 'scratch that' via VoiceCommandEngine"
    },
    {
      text: "Meeting at 3 PM urgent all caps that. Please review PR before standup.",
      action: "In-line case formatting: 'URGENT'"
    }
  ];

  let scenarioIndex = 0;
  let charIndex = 0;
  let isDeleting = false;
  let typingSpeed = 38;

  function typeDemo() {
    const current = demoScenarios[scenarioIndex];
    const fullText = current.text;

    if (!isDeleting) {
      // Typing forward
      if (charIndex <= fullText.length) {
        transcriptEl.textContent = fullText.substring(0, charIndex);
        charIndex++;
        setTimeout(typeDemo, typingSpeed);
      } else {
        // Finished typing phrase, hold for a moment
        demoStatus.textContent = "✓ Injected to Cursor";
        if (soundWave) soundWave.style.opacity = "0.35";
        setTimeout(() => {
          isDeleting = true;
          if (soundWave) soundWave.style.opacity = "1";
          demoStatus.textContent = "Listening (300 WPM)...";
          typeDemo();
        }, 3200);
      }
    } else {
      // Erasing forward to next phrase
      if (charIndex > 0) {
        transcriptEl.textContent = fullText.substring(0, charIndex);
        charIndex -= 2;
        setTimeout(typeDemo, 18);
      } else {
        isDeleting = false;
        scenarioIndex = (scenarioIndex + 1) % demoScenarios.length;
        charIndex = 0;
        setTimeout(typeDemo, 500);
      }
    }
  }

  if (transcriptEl) {
    typeDemo();
  }

  // 3. FAQ Accordion
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const questionBtn = item.querySelector('.faq-question');
    questionBtn.addEventListener('click', () => {
      const isOpen = item.classList.contains('open');
      // Close others
      faqItems.forEach(i => i.classList.remove('open'));
      // Toggle selected
      if (!isOpen) {
        item.classList.add('open');
      }
    });
  });

  // 4. Fetch GitHub Release Stats if online
  const releaseTag = document.getElementById('hero-version-tag');
  fetch('https://api.github.com/repos/abhilashpanda04/Openflow/releases/latest')
    .then(res => res.json())
    .then(data => {
      if (data && data.tag_name && releaseTag) {
        releaseTag.textContent = data.tag_name;
      }
    })
    .catch(() => {
      // fallback to static v0.1.0
    });
});
