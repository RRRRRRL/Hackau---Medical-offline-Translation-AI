// Locally stored phrases for the demo. Clinical language review is still required.
export const languages = { en: 'English', zh: 'Chinese' }

export const questions = [
  { id: 'pain', category: 'Pain', en: 'Where does it hurt?', zh: '你哪里疼？', yesNo: false },
  { id: 'breathing', category: 'Breathing', en: 'Can you breathe normally?', zh: '你能正常呼吸吗？', yesNo: true },
  { id: 'allergy', category: 'Allergy', en: 'Are you allergic to any medication?', zh: '你对任何药物过敏吗？', yesNo: true },
  { id: 'medication', category: 'Medication', en: 'Are you taking any medication?', zh: '你现在正在服用药物吗？', yesNo: true },
  { id: 'consciousness', category: 'Consciousness', en: 'Did you lose consciousness?', zh: '你失去过意识吗？', yesNo: true },
  { id: 'bleeding', category: 'Bleeding', en: 'Are you bleeding?', zh: '你在流血吗？', yesNo: true },
  { id: 'chest-pain', category: 'Chest pain', en: 'Do you have chest pain?', zh: '你胸口疼吗？', yesNo: true },
]
