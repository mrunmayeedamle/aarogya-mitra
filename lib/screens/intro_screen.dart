import 'package:flutter/material.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _controller = PageController();
  int currentPage = 0;

  final List<Map<String, String>> slides = [
    {
      "title": "आरोग्यमित्र",
      "subtitle": "तुमचा AI आरोग्य सहाय्यक",
      "description":
      "तुमची लक्षणे मराठीत लिहा किंवा बोला आणि त्वरित AI आधारित आरोग्य मार्गदर्शन मिळवा."
    },
    {
      "title": "स्मार्ट लक्षण ओळख",
      "subtitle": "लक्षणे ओळखणारी बुद्धिमान प्रणाली",
      "description":
      "तुमची लक्षणे मराठीत टाइप करा किंवा बोला. आमची AI प्रणाली संभाव्य आजार ओळखते."
    },
    {
      "title": "त्वरित आरोग्य मार्गदर्शन",
      "subtitle": "आजारीपणाबाबत त्वरित माहिती",
      "description":
      "संभाव्य आजार, आवश्यक काळजी आणि आरोग्य सल्ला काही सेकंदांत मिळवा."
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),

              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: slides.length,
                  onPageChanged: (index) {
                    setState(() {
                      currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_hospital,
                          size: 100,
                          color: Colors.green.shade700,
                        ),

                        const SizedBox(height: 30),

                        Text(
                          slides[index]["title"]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          slides[index]["subtitle"]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.black54,
                          ),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          slides[index]["description"]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  slides.length,
                      (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: currentPage == index ? 12 : 8,
                    height: currentPage == index ? 12 : 8,
                    decoration: BoxDecoration(
                      color: currentPage == index
                          ? Colors.green.shade700
                          : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {

                    if (currentPage == slides.length - 1) {

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('seenIntro', true);

                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AuthWrapper(),
                        ),
                      );

                    } else {

                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );

                    }
                  },
                  child: Text(
                    currentPage == slides.length - 1
                        ? "Get Started"
                        : "Next",
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}